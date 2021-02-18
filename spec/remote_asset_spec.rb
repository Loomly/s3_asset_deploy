require "spec_helper"

RSpec.describe S3AssetDeploy::RemoteAsset do
  describe "#original_path" do
    it "removes fingerprint after hyphen" do
      asset = described_class.new(
        OpenStruct.new(key: "packs/js/0-3e1f1b9c14ca587bae85.chunk.js")
      )

      expect(asset.original_path).to eq("packs/js/0.chunk.js")
    end
  end

  context "when passing in remove_fingerprint" do
    describe "#original_path" do
      it "removes fingerprint according to remove_fingerint lambda" do
        asset = described_class.new(
          OpenStruct.new(key: "packs/js/0-3e1f1b9c14ca587bae85.chunk.js"),
          remove_fingerprint: ->(path) { path.gsub("bae85", "") }
        )

        expect(asset.original_path).to eq("packs/js/0-3e1f1b9c14ca587.chunk.js")
      end
    end
  end
end
