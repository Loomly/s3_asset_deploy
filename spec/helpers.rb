module Helpers
  def create_remote_assets(*definitions)
    definitions.map do |definition|
      key, last_modified = definition
      last_modified = Time.parse(last_modified) unless last_modified.is_a?(Time)
      S3AssetDeploy::RemoteAsset.new(OpenStruct.new(key: key, last_modified: last_modified))
    end
  end

  def create_local_assets(*paths)
    paths.map { |path| S3AssetDeploy::LocalAsset.new(path) }
  end

  def expect_instance_of_remote_asset_collector_to_receive_assets(times, *definitions)
    expect_any_instance_of(S3AssetDeploy::RemoteAssetCollector).to receive(:assets).exactly(times).times.and_return(
      create_remote_assets(*definitions)
    )
  end

  def expect_instance_of_local_asset_collector_to_receive_assets(times, *paths)
    expect_any_instance_of(S3AssetDeploy::RailsLocalAssetCollector).to receive(:assets).exactly(times).times.and_return(
      create_local_assets(*paths)
    )
  end
end
