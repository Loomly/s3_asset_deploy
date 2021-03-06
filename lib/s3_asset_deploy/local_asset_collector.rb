# frozen_string_literal: true

class S3AssetDeploy::LocalAssetCollector
  def initialize(remove_fingerprint: nil)
    @remove_fingerprint = remove_fingerprint
  end

  def assets
    []
  end

  def asset_paths
    assets.map(&:path)
  end

  def asset_map
    assets.map do |asset|
      [asset.original_path, asset]
    end.to_h
  end

  def original_asset_paths
    assets.map(&:original_path)
  end

  def full_file_path(asset_path)
    asset_path
  end
end
