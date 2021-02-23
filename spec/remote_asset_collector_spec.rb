require "spec_helper"

RSpec.describe S3AssetDeploy::RemoteAssetCollector do
  subject { described_class.new("test-bucket" ) }

  let(:s3_client) do
    Class.new do
      def initialize(&block)
        @list_objects_v2 = block
      end

      def list_objects_v2(*args)
        [
          OpenStruct.new(
            contents: @list_objects_v2 ? @list_objects_v2.call(*args) : []
          )
        ]
      end
    end
  end

  let(:s3_client_instance) { s3_client.new }

  before { allow_any_instance_of(described_class).to receive(:s3) { s3_client_instance } }


  context "with removal manifest file in bucket" do
    let(:s3_client_instance) do
      s3_client.new do
        [
          OpenStruct.new(key: S3AssetDeploy::RemovalManifest::PATH)
        ]
      end
    end

    describe "#assets" do
      it "doesn't include removal manifest file in assets" do
        expect(subject.assets).to match_array([])
      end
    end
  end
end
