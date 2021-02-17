require "s3_asset_deploy/asset_helper"

class S3AssetDeploy::LocalAsset
  attr_reader :path

  def initialize(path)
    @path = path
  end

  def original_path
    @original_path ||= S3AssetDeploy::AssetHelper.remove_fingerprint(path)
  end

  def full_path
    File.join(public_path, path)
  end

  def mime_type
    S3AssetDeploy::AssetHelper.mime_type_for_path(path).to_s
  end

  def ==(other_asset)
    path == other_asset.path
  end

  protected

  def public_path
    ::Rails.public_path
  end
end
