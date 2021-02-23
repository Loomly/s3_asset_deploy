require "json"

class S3AssetDeploy::RemovalManifest
  attr_reader :bucket_name

  PATH = "s3-asset-deploy-removal-manifest.json".freeze

  def initialize(bucket_name, s3_client_options: {})
    @bucket_name = bucket_name
    @loaded = false
    @manifest = {}
    @s3_client_options = {
      region: "us-east-1",
      logger: @logger
    }.merge(s3_client_options)
  end

  def s3
    @s3 ||= Aws::S3::Client.new(@s3_client_options)
  end

  def load
    return true if loaded?
    @manifest = fetch_manifest
    @loaded = true
  rescue Aws::S3::Errors::NoSuchKey
    @manifest = {}
    @loaded = true
  end

  def loaded?
    @loaded
  end

  def save
    return unless loaded?
    s3.put_object({
      bucket: bucket_name,
      key: PATH,
      body: @manifest.to_json,
      acl: "private",
      content_type: "application/json"
    })
  end

  def keys
    @manifest.keys
  end

  def delete(key)
    return unless loaded?
    @manifest.delete(key)
  end

  def [](key)
    @manifest[key]
  end

  def []=(key, value)
    return unless loaded?
    @manifest[key] = value
  end

  def to_h
    @manifest
  end

  def to_s
    @manifest.to_s
  end

  def inspect
    "#<#{self.class.name}:#{"0x0000%x" % (object_id << 1)} @bucket_name='#{bucket_name}'>"
  end

  private

  def fetch_manifest
    resp = s3.get_object({
      bucket: bucket_name,
      key: PATH
    })

    JSON.parse(resp.body.read)
  end
end
