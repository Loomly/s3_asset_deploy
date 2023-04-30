# frozen_string_literal: true

require "s3_asset_deploy/rails_local_asset"
require "s3_asset_deploy/local_asset_collector"

class S3AssetDeploy::RailsLocalAssetCollector < S3AssetDeploy::LocalAssetCollector
  def assets
    assets_from_manifest + pack_assets
  end

  def assets_from_manifest
    manifest = ::Sprockets::Manifest.new(
      ::ActionView::Base.assets_manifest.environment,
      ::ActionView::Base.assets_manifest.filename
    )
    manifest.assets.values.map do |f|
      S3AssetDeploy::RailsLocalAsset.new(
        File.join(assets_prefix, f),
        remove_fingerprint: @remove_fingerprint
      )
    end
  end

  def pack_assets
    return [] unless defined?(::Webpacker)

    Dir.chdir(public_path) do
      packs_dir = ::Webpacker.config.public_output_path.relative_path_from(public_path)

      Dir[File.join(packs_dir, "/**/**")]
        .select { |path| File.file?(path) }
        .reject { |path| path.ends_with?(".gz") || path.ends_with?("manifest.json") }
        .map { |path| S3AssetDeploy::RailsLocalAsset.new(path, remove_fingerprint: @remove_fingerprint) }
    end
  end

  private

  def public_path
    ::Rails.public_path
  end

  def assets_prefix
    ::Rails.application.config.assets.prefix.sub(/^\//, "")
  end
end
