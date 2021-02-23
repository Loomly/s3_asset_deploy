# frozen_string_literal: true

require "s3_asset_deploy/local_asset"

class S3AssetDeploy::RailsLocalAsset < S3AssetDeploy::LocalAsset
  attr_reader :path

  def full_path
    File.join(public_path, path)
  end

  protected

  def public_path
    ::Rails.public_path
  end
end
