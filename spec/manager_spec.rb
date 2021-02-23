require "spec_helper"

RSpec.describe S3AssetDeploy::Manager do
  subject { described_class.new("test-bucket", logger: Logger.new(IO::NULL) ) }
  let(:s3_client) do
    Class.new do
      def put_object(*args)
      end

      def delete_objects(*args)
      end
    end
  end

  let(:s3_client_instance) { s3_client.new }

  let(:removal_manifest_s3_client) do
    Class.new do
      def initialize(&block)
        @get_object = block
      end

      def put_object(*args)
      end

      def get_object(*args)
        OpenStruct.new(
          body: StringIO.new((@get_object ? @get_object.call(*args) : {}).to_json)
        )
      end
    end
  end

  let(:removal_manifest_s3_client_instance) { removal_manifest_s3_client.new }

  before { allow_any_instance_of(described_class).to receive(:s3) { s3_client_instance } }
  before { allow_any_instance_of(S3AssetDeploy::RemovalManifest).to receive(:s3) { removal_manifest_s3_client_instance } }

  describe "#local_assets_to_upload" do
    it "only returns assets not on remote" do
      expect_instance_of_remote_asset_collector_to_receive_assets(
        1,
        ["assets/file-1-12345.jpg", "2018-05-01 15:38:31 UTC"]
      )
      expect_instance_of_local_asset_collector_to_receive_assets(
        1,
        "assets/file-1-12345.jpg",
        "assets/file-2-34567.jpg",
        "assets/file-3-9876666.jpg"
      )

      expect(subject.local_assets_to_upload).to contain_exactly(
        *create_local_assets("assets/file-2-34567.jpg", "assets/file-3-9876666.jpg")
      )
    end
  end

  describe "#upload" do
    before { allow(File).to receive(:file?) { true } }

    it "uploads new assets" do
      expect_instance_of_remote_asset_collector_to_receive_assets(
        1,
        ["assets/file-2-34567.jpg", "2018-05-01 15:38:31 UTC"],
        ["assets/file-3-9876666.jpg", "2018-05-01 15:38:31 UTC"]
      )

      expect_instance_of_local_asset_collector_to_receive_assets(
        4,
        "assets/file-1-12345.jpg",
        "assets/file-4-3333.jpg",
        "assets/file-3-9876666.jpg"
      )

      expect(subject).to receive(:upload_asset).with(
        S3AssetDeploy::LocalAsset.new("assets/file-1-12345.jpg")
      )
      expect(subject).to receive(:upload_asset).with(
        S3AssetDeploy::LocalAsset.new("assets/file-4-3333.jpg")
      )
      expect(subject.upload).to contain_exactly("assets/file-1-12345.jpg", "assets/file-4-3333.jpg")
    end

    context "with removed files in removal manifest" do
      let(:removal_manifest_s3_client_instance) do
        removal_manifest_s3_client.new do
          {
            "assets/file-2-34567.jpg" => (Time.now - 172801).utc.iso8601,
            "assets/file-3-9876666.jpg" => (Time.now - 172799).utc.iso8601
          }
        end
      end

      it "removes re-added assets from removal manifest" do
        expect_instance_of_remote_asset_collector_to_receive_assets(
          1,
          ["assets/file-2-34567.jpg", "2018-05-01 15:38:31 UTC"],
          ["assets/file-3-9876666.jpg", "2018-05-01 15:38:31 UTC"]
        )

        expect_instance_of_local_asset_collector_to_receive_assets(
          4,
          "assets/file-1-12345.jpg",
          "assets/file-3-9876666.jpg"
        )

        expect(subject.removal_manifest).to receive(:delete).with("assets/file-3-9876666.jpg")
        expect(subject.removal_manifest).to receive(:save)
        expect(subject).to receive(:upload_asset).with(S3AssetDeploy::LocalAsset.new("assets/file-1-12345.jpg"))
        expect(subject.upload).to contain_exactly("assets/file-1-12345.jpg")
      end
    end
  end

  describe "#clean" do
    it "adds removed files to removal manifest" do
      Timecop.freeze(Time.now) do
        expect_instance_of_remote_asset_collector_to_receive_assets(
          2,
          ["assets/file-1-12345.jpg", "2018-05-01 15:38:31 UTC"],
          ["assets/file-2-34567.jpg", "2018-05-01 15:38:31 UTC"],
          ["assets/file-3-9876666.jpg", "2018-05-01 15:38:31 UTC"]
        )

        expect_instance_of_local_asset_collector_to_receive_assets(
          4,
          "assets/file-1-12345.jpg"
        )

        expect(subject.removal_manifest).to receive(:load)
        expect(subject.removal_manifest).to receive(:[]=).once.with(
          "assets/file-2-34567.jpg",
          Time.now.utc.iso8601
        )
        expect(subject.removal_manifest).to receive(:[]=).once.with(
          "assets/file-3-9876666.jpg",
          Time.now.utc.iso8601
        )
        expect(subject.removal_manifest).to receive(:save)

        expect(subject.clean).to match_array([])
      end
    end

    context "with removed files in removal manifest" do
      let(:removal_manifest_s3_client_instance) do
        removal_manifest_s3_client.new do
          {
            "assets/file-2-34567.jpg" => (Time.now - 172801).utc.iso8601,
            "assets/file-3-9876666.jpg" => (Time.now - 172799).utc.iso8601
          }
        end
      end

      it "deletes remote assets only after 'removed_ttl'" do
        Timecop.freeze(Time.now) do
          expect_instance_of_remote_asset_collector_to_receive_assets(
            2,
            ["assets/file-1-12345.jpg", "2018-05-01 15:38:31 UTC"],
            ["assets/file-2-34567.jpg", "2018-05-01 15:38:31 UTC"],
            ["assets/file-3-9876666.jpg", "2018-05-01 15:38:31 UTC"]
          )

          expect_instance_of_local_asset_collector_to_receive_assets(
            4,
            "assets/file-1-12345.jpg"
          )

          expect(subject.clean(removed_ttl: 172800)).to contain_exactly("assets/file-2-34567.jpg")
        end
      end
    end

    it "keeps old versions up to 'version_limit'" do
      expect_instance_of_remote_asset_collector_to_receive_assets(
        2,
        ["assets/file-1-123.jpg", "2018-05-01 15:38:31 UTC"],
        ["assets/file-1-456.jpg", "2018-05-02 15:38:31 UTC"],
        ["assets/file-1-789.jpg", "2018-05-03 15:38:31 UTC"],
        ["assets/file-1-987.jpg", "2018-05-04 15:38:31 UTC"],
        ["assets/file-2-123.jpg", "2018-05-01 15:38:31 UTC"],
        ["assets/file-2-456.jpg", "2018-05-02 15:38:31 UTC"],
        ["assets/file-2-789.jpg", "2018-05-03 15:38:31 UTC"],
        ["assets/file-3-9876666.jpg", "2018-05-01 15:38:31 UTC"]
      )
      expect_instance_of_local_asset_collector_to_receive_assets(
        4,
        "assets/file-1-987.jpg",
        "assets/file-2-123.jpg",
        "assets/file-3-9876666.jpg"
      )

      expect(subject.clean(version_limit: 2)).to contain_exactly("assets/file-1-123.jpg")
    end

    it "waits atleast 'version_ttl' seconds before deleting old versions" do
      Timecop.freeze(Time.now) do
        expect_instance_of_remote_asset_collector_to_receive_assets(
          4,
          ["assets/file-1-123.jpg", (Time.now - 4)],
          ["assets/file-1-456.jpg", (Time.now - 3)],
          ["assets/file-1-789.jpg", (Time.now - 2)],
          ["assets/file-1-987.jpg", (Time.now - 1)]
        )
        expect_instance_of_local_asset_collector_to_receive_assets(
          8,
          "assets/file-1-987.jpg"
        )

        expect(subject.clean).to be_empty

        Timecop.travel(Time.now + 3600)
        expect(subject.clean(version_ttl: 3600)).to contain_exactly("assets/file-1-123.jpg")
      end
    end

    it "raises DuplicateAssetsError if duplicate local assets" do
      expect_instance_of_local_asset_collector_to_receive_assets(
        2,
        "assets/file-1-987.jpg",
        "assets/file-1-987.jpg"
      )

      expect { subject.clean }.to raise_error(S3AssetDeploy::DuplicateAssetsError)
    end
  end
end
