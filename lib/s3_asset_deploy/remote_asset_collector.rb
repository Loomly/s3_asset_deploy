# frozen_string_literal: true

require "aws-sdk-s3"
require "s3_asset_deploy/removal_manifest"
require "s3_asset_deploy/remote_asset"

class S3AssetDeploy::RemoteAssetCollector
  attr_reader :bucket_name

  def initialize(bucket_name, s3_client_options: {}, remove_fingerprint: nil)
    @bucket_name = bucket_name
    @remove_fingerprint = remove_fingerprint
    @s3_client_options = {
      region: "us-east-1",
      logger: @logger
    }.merge(s3_client_options)
  end

  def s3
    @s3 ||= Aws::S3::Client.new(@s3_client_options)
  end

  def assets
    @assets ||= s3.list_objects_v2(bucket: bucket_name).each_with_object([]) do |response, array|
      remote_assets = response
        .contents
        .reject { |obj| obj.key == S3AssetDeploy::RemovalManifest::PATH }
        .map do |obj|
          S3AssetDeploy::RemoteAsset.new(obj, remove_fingerprint: @remove_fingerprint)
        end

      array.concat(remote_assets)
    end
  end

  def clear_cache
    @assets = nil
  end

  def asset_paths
    assets.map(&:path)
  end

  def grouped_assets
    assets.group_by(&:original_path)
  end

  def to_s
    "#<#{self.class.name}:#{"0x0000%x" % (object_id << 1)} @bucket_name='#{bucket_name}'>"
  end

  def inspect
    to_s
  end
end
