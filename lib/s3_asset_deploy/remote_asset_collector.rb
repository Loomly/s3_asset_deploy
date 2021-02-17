# frozen_string_literal: true

require "aws-sdk-s3"
require "s3_asset_deploy/remote_asset"

class S3AssetDeploy::RemoteAssetCollector
  attr_reader :bucket_name

  def initialize(bucket_name, s3_client_options: {})
    @bucket_name = bucket_name
    @s3_client_options = {
      region: "us-east-1",
      logger: @logger
    }.merge(s3_client_options)
  end

  def s3
    @s3 ||= Aws::S3::Client.new(@s3_client_options)
  end

  def assets
    s3.list_objects_v2(bucket: bucket_name).each_with_object([]) do |response, array|
      array.concat(response.contents.map { |obj| S3AssetDeploy::RemoteAsset.new(obj) })
    end
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
