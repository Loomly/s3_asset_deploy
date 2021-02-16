require "s3_asset_deploy/asset_helper"

class S3AssetDeploy::RemoteAsset
  attr_reader :s3_object

  def initialize(s3_object)
    @s3_object = s3_object
  end

  def original_path
    @original_path ||= AssetHelper.remove_fingerprint(path)
  end

  def last_modified
    s3_object.last_modified
  end

  def path
    s3_object.key
  end

  def ==(other_asset)
    path == other_asset.path
  end
end
