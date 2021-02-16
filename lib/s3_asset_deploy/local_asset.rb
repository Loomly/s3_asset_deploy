require "s3_asset_deploy/asset_helper"

class S3AssetDeploy::LocalAsset
  attr_reader :path

  def initialize(path)
    @path = path
  end

  def original_path
    @original_path ||= AssetHelper.remove_fingerprint(path)
  end

  def full_path
    File.join(public_path, path)
  end

  def mime_type
    AssetHelper.mime_type_for_extension(path).to_s
  end

  def to_s
    path
  end

  protected

  def public_path
    ::Rails.public_path
  end
end
