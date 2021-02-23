# frozen_string_literal: true

require "s3_asset_deploy/asset_helper"

class S3AssetDeploy::LocalAsset
  attr_reader :path

  def initialize(path, remove_fingerprint: nil)
    @path = path
    @remove_fingerprint = remove_fingerprint
  end

  def original_path
    @original_path ||=
      if @remove_fingerprint
        @remove_fingerprint.call(path)
      else
        S3AssetDeploy::AssetHelper.remove_fingerprint(path)
      end
  end

  def full_path
    File.join(ENV["PWD"], "public", path)
  end

  def mime_type
    S3AssetDeploy::AssetHelper.mime_type_for_path(path).to_s
  end

  def ==(other_asset)
    path == other_asset.path
  end

  def to_s
    path
  end
end
