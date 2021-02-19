require "json"
require "s3_asset_deploy/errors"

class S3AssetDeploy::RemovalManifest
  attr_reader :key, :bucket_name, :manifest

  def initialize(key, bucket_name, s3_client_options: {})
    @key = key
    @bucket_name = bucket_name
    @loaded = false
    @s3_client_options = {
      region: "us-east-1",
      logger: @logger
    }.merge(s3_client_options)
  end

  def s3
    @s3 ||= Aws::S3::Client.new(@s3_client_options)
  end

  def load
    resp = s3.get_object({
      bucket: bucket_name,
      key: key
    })

    @manifest = JSON.parse(resp.body.read)
    @loaded = true
  rescue Aws::S3::Errors::NoSuchKey
    @manifest = {}
    @loaded = true
  end

  def loaded?
    @loaded
  end

  def save
    s3.put_object({
      bucket: bucket_name,
      key: key,
      body: @manifest.to_json,
      acl: "private",
      content_type: "application/json"
    })
  end

  def delete(manifest_key)
    @manifest.delete(manifest_key)
  end

  def [](manifest_key)
    raise S3AssetDeploy::ManifestUnloadedError unless loaded?
    @manifest[manifest_key]
  end

  def []=(manifest_key, manifest_value)
    @manifest[manifest_key] = manifest_value
  end

  def to_s
    @manifest.to_s
  end

  def inspect
    "#<#{self.class.name}:#{"0x0000%x" % (object_id << 1)} @key='#{key}' @bucket_name='#{bucket_name}'>"
  end
end
