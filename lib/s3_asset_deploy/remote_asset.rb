# frozen_string_literal: true

require "s3_asset_deploy/asset_helper"

class S3AssetDeploy::RemoteAsset
  attr_reader :s3_object

  def initialize(s3_object, remove_fingerprint: nil)
    @s3_object = s3_object
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

  def last_modified
    s3_object.last_modified
  end

  def path
    s3_object.key
  end

  def ==(other_asset)
    path == other_asset.path
  end

  def to_s
    path
  end
end
