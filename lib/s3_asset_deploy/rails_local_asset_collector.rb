require "s3_asset_deploy/local_asset_collector"

class S3AssetDeploy::RailsLocalAssetCollector < S3AssetDeploy::LocalAssetCollector
  def local_asset_paths
    assets_from_manifest + pack_assets
  end

  def assets_from_manifest
    manifest = Sprockets::Manifest.new(ActionView::Base.assets_manifest.environment, ActionView::Base.assets_manifest.dir)
    manifest.assets.values.map { |f| File.join(assets_prefix, f) }
  end

  def pack_assets
    return [] unless defined?(Webpacker)

    Dir.chdir(public_path) do
      packs_dir = Webpacker.config.public_output_path.relative_path_from(public_path)

      Dir[File.join(packs_dir, "/**/**")]
        .select { |file| File.file?(file) }
        .reject { |file| file.ends_with?(".gz") || file.ends_with?("manifest.json") }
    end
  end

  private

  def assets_prefix
    ::Rails.application.config.assets.prefix.sub(/^\//, "")
  end

  def public_path
    ::Rails.public_path
  end
end
