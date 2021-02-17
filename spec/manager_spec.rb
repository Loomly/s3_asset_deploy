require "spec_helper"

RSpec.describe S3AssetDeploy::Manager do
  subject { described_class.new("test-bucket", logger: Logger.new(IO::NULL) ) }
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

  describe "#local_assets_to_upload" do
    it "should only return assets not on remote" do
      expect_any_instance_of(S3AssetDeploy::RemoteAssetCollector).to receive(:assets).once.and_return(
        create_remote_assets(["assets/file-1-12345.jpg", "2018-05-01 15:38:31 UTC"])
      )
      expect_any_instance_of(S3AssetDeploy::RailsLocalAssetCollector).to receive(:assets).once.and_return(
        create_local_assets(
          "assets/file-1-12345.jpg",
          "assets/file-2-34567.jpg",
          "assets/file-3-9876666.jpg"
        )
      )

      expect(subject.local_assets_to_upload).to contain_exactly(
        *create_local_assets("assets/file-2-34567.jpg", "assets/file-3-9876666.jpg")
      )
    end
  end

  describe "#clean_assets" do
    it "should tag untagged removed files" do
      Timecop.freeze(Time.now) do
        remote_assets = create_remote_assets(
          ["assets/file-1-12345.jpg", "2018-05-01 15:38:31 UTC"],
          ["assets/file-2-34567.jpg", "2018-05-01 15:38:31 UTC"],
          ["assets/file-3-9876666.jpg", "2018-05-01 15:38:31 UTC"]
        )
        expect_any_instance_of(S3AssetDeploy::RemoteAssetCollector).to receive(:assets).twice.and_return(remote_assets)
        expect_any_instance_of(S3AssetDeploy::RailsLocalAssetCollector).to receive(:assets).exactly(4).times.and_return(
          create_local_assets("assets/file-1-12345.jpg")
        )

        expect(subject).to receive(:put_object_tagging).once.with(
          "assets/file-2-34567.jpg",
          array_including(key: :removed_at, value: Time.now.utc.iso8601)
        )
        expect(subject).to receive(:put_object_tagging).once.with(
          "assets/file-3-9876666.jpg",
          array_including(key: :removed_at, value: Time.now.utc.iso8601)
        )

        expect(subject.clean_assets).to match_array([])
      end
    end

    it "should delete remote assets only after 'removed_ttl'" do
      Timecop.freeze(Time.now) do
        remote_assets = create_remote_assets(
          ["assets/file-1-12345.jpg", "2018-05-01 15:38:31 UTC"],
          ["assets/file-2-34567.jpg", "2018-05-01 15:38:31 UTC"],
          ["assets/file-3-9876666.jpg", "2018-05-01 15:38:31 UTC"]
        )
        expect_any_instance_of(S3AssetDeploy::RemoteAssetCollector).to receive(:assets).twice.and_return(remote_assets)
        expect_any_instance_of(S3AssetDeploy::RailsLocalAssetCollector).to receive(:assets).exactly(4).times.and_return(
          create_local_assets("assets/file-1-12345.jpg")
        )

        expect(subject).to receive(:get_object_tagging).once
          .with("assets/file-2-34567.jpg")
          .and_return(OpenStruct.new(tag_set: [{ key: "removed_at", value: (Time.now - 172801).utc.iso8601 }]))
        expect(subject).to receive(:get_object_tagging).once
          .with("assets/file-3-9876666.jpg")
          .and_return(OpenStruct.new(tag_set: [{ key: "removed_at", value: (Time.now - 172799).utc.iso8601 }]))

        expect(subject.clean_assets(removed_ttl: 172800)).to contain_exactly("assets/file-2-34567.jpg")
      end
    end

    it "should keep old versions up to 'version_limit'" do
      expect_any_instance_of(S3AssetDeploy::RemoteAssetCollector).to receive(:assets).twice.and_return(create_remote_assets(
        ["assets/file-1-123.jpg", "2018-05-01 15:38:31 UTC"],
        ["assets/file-1-456.jpg", "2018-05-02 15:38:31 UTC"],
        ["assets/file-1-789.jpg", "2018-05-03 15:38:31 UTC"],
        ["assets/file-1-987.jpg", "2018-05-04 15:38:31 UTC"],
        ["assets/file-2-123.jpg", "2018-05-01 15:38:31 UTC"],
        ["assets/file-2-456.jpg", "2018-05-02 15:38:31 UTC"],
        ["assets/file-2-789.jpg", "2018-05-03 15:38:31 UTC"],
        ["assets/file-3-9876666.jpg", "2018-05-01 15:38:31 UTC"]
      ))

      expect_any_instance_of(S3AssetDeploy::RailsLocalAssetCollector).to receive(:assets).exactly(4).times.and_return(
        create_local_assets("assets/file-1-987.jpg", "assets/file-2-123.jpg", "assets/file-3-9876666.jpg")
      )

      expect(subject.clean_assets(version_limit: 2)).to contain_exactly("assets/file-1-123.jpg")
    end

    it "should wait atleast 'version_ttl' seconds before deleting old versions" do
      Timecop.freeze(Time.now) do
        expect_any_instance_of(S3AssetDeploy::RemoteAssetCollector).to receive(:assets).exactly(4).times.and_return(create_remote_assets(
          ["assets/file-1-123.jpg", (Time.now - 4)],
          ["assets/file-1-456.jpg", (Time.now - 3)],
          ["assets/file-1-789.jpg", (Time.now - 2)],
          ["assets/file-1-987.jpg", (Time.now - 1)]
        ))

        expect_any_instance_of(S3AssetDeploy::RailsLocalAssetCollector).to receive(:assets).exactly(8).times.and_return(
          create_local_assets("assets/file-1-987.jpg")
        )

        expect(subject.clean_assets).to be_empty

        Timecop.travel(Time.now + 3600)
        expect(subject.clean_assets(version_ttl: 3600)).to contain_exactly("assets/file-1-123.jpg")
      end
    end

    it "should raise DuplicateAssetsError if duplicate local assets" do
      expect_any_instance_of(S3AssetDeploy::RailsLocalAssetCollector).to receive(:assets).twice.times.and_return(
        create_local_assets("assets/file-1-987.jpg", "assets/file-1-987.jpg")
      )

      expect { subject.clean_assets }.to raise_error(described_class::DuplicateAssetsError)
    end
  end
end
