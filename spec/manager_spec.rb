require "spec_helper"

RSpec.describe S3AssetDeploy::Manager do
  subject { described_class.new("test-bucket") }
  let(:s3_client) do
    Class.new do
      def put_object(*args)
      end

      def delete_objects(*args)
      end

      def get_object_tagging(*args)
        OpenStruct.new(tag_set: [])
      end

      def put_object_tagging(*args)
      end
    end
  end

  let(:s3_client_instance) { s3_client.new }

  before { allow_any_instance_of(described_class).to receive(:s3) { s3_client_instance } }
  before { allow_any_instance_of(described_class).to receive(:log) {} }

  describe "#local_assets_to_upload" do
    it "should only return assets not on remote" do
      expect(subject).to receive(:remote_assets).at_least(:once).and_return([
        OpenStruct.new(key: "assets/file-1-12345.jpg", last_modified: Time.parse("2018-05-01 15:38:31 UTC")),
      ])
      expect(subject).to receive(:local_asset_paths).at_least(:once).and_return([
        "assets/file-1-12345.jpg",
        "assets/file-2-34567.jpg",
        "assets/file-3-9876666.jpg"
      ])

      expect(subject.local_assets_to_upload).to contain_exactly("assets/file-2-34567.jpg", "assets/file-3-9876666.jpg")
    end
  end

  describe "#clean_assets" do
    it "should tag untagged removed files" do
      Timecop.freeze(Time.now) do
        remote_assets = [
          OpenStruct.new(key: "assets/file-1-12345.jpg", last_modified: Time.parse("2018-05-01 15:38:31 UTC")),
          OpenStruct.new(key: "assets/file-2-34567.jpg", last_modified: Time.parse("2018-05-01 15:38:31 UTC")),
          OpenStruct.new(key: "assets/file-3-9876666.jpg", last_modified: Time.parse("2018-05-01 15:38:31 UTC"))
        ]
        expect(subject).to receive(:remote_assets).at_least(:once).and_return(remote_assets)
        expect(subject).to receive(:local_asset_paths).at_least(:once).and_return([
          "assets/file-1-12345.jpg"
        ])

        expect(s3_client_instance).to receive(:put_object_tagging).once.with(
          "assets/file-2-34567.jpg",
          array_including(key: :removed_at, value: Time.now.utc.iso8601)
        )
        expect(s3_client_instance).to receive(:put_object_tagging).once.with(
          "assets/file-3-9876666.jpg",
          array_including(key: :removed_at, value: Time.now.utc.iso8601)
        )

        expect(subject.clean_assets).to match_array([])
      end
    end

    it "should delete remote assets only after 'removed_age'" do
      Timecop.freeze(Time.now) do
        remote_assets = [
          OpenStruct.new(key: "assets/file-1-12345.jpg", last_modified: Time.parse("2018-05-01 15:38:31 UTC")),
          OpenStruct.new(key: "assets/file-2-34567.jpg", last_modified: Time.parse("2018-05-01 15:38:31 UTC")),
          OpenStruct.new(key: "assets/file-3-9876666.jpg", last_modified: Time.parse("2018-05-01 15:38:31 UTC"))
        ]
        expect(subject).to receive(:remote_assets).at_least(:once).and_return(remote_assets)
        expect(subject).to receive(:local_asset_paths).at_least(:once).and_return([
          "assets/file-1-12345.jpg"
        ])

        expect(s3_client_instance).to receive(:get_object_tagging).once
          .with("assets/file-2-34567.jpg")
          .and_return(OpenStruct.new(tag_set: [{ key: "removed_at", value: (Time.now - 172801).utc.iso8601 }]))
        expect(s3_client_instance).to receive(:get_object_tagging).once
          .with("assets/file-3-9876666.jpg")
          .and_return(OpenStruct.new(tag_set: [{ key: "removed_at", value: (Time.now - 172799).utc.iso8601 }]))

        expect(subject.clean_assets(removed_age: 172800)).to contain_exactly("assets/file-2-34567.jpg")
      end
    end

    it "should keep old versions up to 'count'" do
      expect(subject).to receive(:remote_assets).at_least(:once).and_return([
        OpenStruct.new(key: "assets/file-1-123.jpg", last_modified: Time.parse("2018-05-01 15:38:31 UTC")),
        OpenStruct.new(key: "assets/file-1-456.jpg", last_modified: Time.parse("2018-05-02 15:38:31 UTC")),
        OpenStruct.new(key: "assets/file-1-789.jpg", last_modified: Time.parse("2018-05-03 15:38:31 UTC")),
        OpenStruct.new(key: "assets/file-1-987.jpg", last_modified: Time.parse("2018-05-04 15:38:31 UTC")),
        OpenStruct.new(key: "assets/file-2-123.jpg", last_modified: Time.parse("2018-05-01 15:38:31 UTC")),
        OpenStruct.new(key: "assets/file-2-456.jpg", last_modified: Time.parse("2018-05-02 15:38:31 UTC")),
        OpenStruct.new(key: "assets/file-2-789.jpg", last_modified: Time.parse("2018-05-03 15:38:31 UTC")),
        OpenStruct.new(key: "assets/file-3-9876666.jpg", last_modified: Time.parse("2018-05-01 15:38:31 UTC"))
      ])

      expect(subject).to receive(:local_asset_paths).at_least(:once).and_return([
        "assets/file-1-987.jpg",
        "assets/file-2-123.jpg",
        "assets/file-3-9876666.jpg"
      ])

      expect(subject.clean_assets(count: 2)).to contain_exactly("assets/file-1-123.jpg")
    end

    it "should wait atleast 'age' seconds before deleting old versions" do
      Timecop.freeze(Time.now) do
        expect(subject).to receive(:remote_assets).at_least(:once).and_return([
          OpenStruct.new(key: "assets/file-1-123.jpg", last_modified: (Time.now - 4)),
          OpenStruct.new(key: "assets/file-1-456.jpg", last_modified: (Time.now - 3)),
          OpenStruct.new(key: "assets/file-1-789.jpg", last_modified: (Time.now - 2)),
          OpenStruct.new(key: "assets/file-1-987.jpg", last_modified: (Time.now - 1))
        ])

        expect(subject).to receive(:local_asset_paths).at_least(:once).and_return([
          "assets/file-1-987.jpg"
        ])

        expect(subject.clean_assets).to be_empty

        Timecop.travel(Time.now + 3600)
        expect(subject.clean_assets).to contain_exactly("assets/file-1-123.jpg")
      end
    end

    it "should raise DuplicateAssetsError if duplicate local assets" do
      expect(subject).to receive(:local_asset_paths).at_least(:once).and_return([
        "assets/file-1-987.jpg",
        "assets/file-1-987.jpg"
      ])

      expect { subject.clean_assets }.to raise_error(described_class::DuplicateAssetsError)
    end
  end

  describe "#remove_fingerprint" do
    it "should account for multiple extensions" do
      expect(subject.remove_fingerprint("packs/js/0-3e1f1b9c14ca587bae85.chunk.js")).to eq("packs/js/0.chunk.js")
    end

    it "should handle multiple hyphens" do
      expect(subject.remove_fingerprint("packs/js/pdf-post-previews-bundle-c574a9fdf0c69f19cce8.chunk.js")).to eq("packs/js/pdf-post-previews-bundle.chunk.js")
    end

    it "should handle tilde" do
      expect(subject.remove_fingerprint("packs/js/runtime~mobile-bundle-298e884ee611bb56b6ca.js.map")).to eq("packs/js/runtime~mobile-bundle.js.map")
    end

    it "should handle single extentions" do
      expect(subject.remove_fingerprint("assets/bootstrap/glyphicons-halflings-regular-42f60659d265c1a3c30f9fa42abcbb56bd4a53af4d83d316d6dd7a36903c43e5.svg")).to eq("assets/bootstrap/glyphicons-halflings-regular.svg")
    end

    it "should log issue if no match" do
      expect(subject).to receive(:log).with("WARNING: No fingerprint found for packs/js/0.chunk.js!")
      expect(subject.remove_fingerprint("packs/js/0.chunk.js")).to eq("packs/js/0.chunk.js")
    end
  end

  describe "#mime_type_for" do
    it "should return application/json for javascript map files" do
      expect(subject.mime_type_for("packs/js/runtime~mobile-bundle-298e884ee611bb56b6ca.js.map")).to eq("application/json")
    end
  end
end
