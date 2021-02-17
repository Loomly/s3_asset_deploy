require "spec_helper"

RSpec.describe S3AssetDeploy::AssetHelper do
  describe ".remove_fingerprint" do
    it "should account for multiple extensions" do
      expect(described_class.remove_fingerprint("packs/js/0-3e1f1b9c14ca587bae85.chunk.js")).to eq("packs/js/0.chunk.js")
    end

    it "should handle multiple hyphens" do
      expect(described_class.remove_fingerprint("packs/js/pdf-post-previews-bundle-c574a9fdf0c69f19cce8.chunk.js")).to eq("packs/js/pdf-post-previews-bundle.chunk.js")
    end

    it "should handle tilde" do
      expect(described_class.remove_fingerprint("packs/js/runtime~mobile-bundle-298e884ee611bb56b6ca.js.map")).to eq("packs/js/runtime~mobile-bundle.js.map")
    end

    it "should handle single extentions" do
      expect(described_class.remove_fingerprint("assets/bootstrap/glyphicons-halflings-regular-42f60659d265c1a3c30f9fa42abcbb56bd4a53af4d83d316d6dd7a36903c43e5.svg")).to eq("assets/bootstrap/glyphicons-halflings-regular.svg")
    end
  end

  describe ".mime_type_for_path" do
    it "should return application/json for javascript map files" do
      expect(described_class.mime_type_for_path("packs/js/runtime~mobile-bundle-298e884ee611bb56b6ca.js.map")).to eq("application/json")
    end
  end
end
