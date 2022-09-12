require "json"

class S3AssetDeploy::RemovalManifest
  attr_reader :bucket_name

  PATH = "s3-asset-deploy-removal-manifest.json".freeze

  def initialize(bucket_name, s3_client_options: {})
    @bucket_name = bucket_name
    @loaded = false
    @changed = false
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

  def changed?
    @changed
  end

  def save
    return false unless loaded?
    return true unless changed?

    s3.put_object({
      bucket: bucket_name,
      key: PATH,
      body: @manifest.to_json,
      content_type: "application/json"
    })

    @changed = false

    true
  end

  def keys
    @manifest.keys
  end

  def delete(key)
    return unless loaded?
    @changed = true
    @manifest.delete(key)
  end

  def [](key)
    @manifest[key]
  end

  def []=(key, value)
    return unless loaded?
    @changed = true
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
