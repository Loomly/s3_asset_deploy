class S3AssetDeploy::LocalAssetCollector
  def local_asset_paths
    []
  end

  def full_file_path(asset_path)
    asset_path
  end
end
