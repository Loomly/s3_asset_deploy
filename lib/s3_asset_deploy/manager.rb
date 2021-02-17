# frozen_string_literal: true

require "logger"
require "time"
require "aws-sdk-s3"
require "s3_asset_deploy/errors"
require "s3_asset_deploy/rails_local_asset_collector"
require "s3_asset_deploy/remote_asset_collector"

class S3AssetDeploy::Manager
  attr_reader :bucket_name, :logger, :local_asset_collector, :remote_asset_collector

  def initialize(bucket_name, s3_client_options: {}, logger: nil, local_asset_collector: nil, upload_asset_options: {})
    @bucket_name = bucket_name.to_s
    @logger = logger || Logger.new(STDOUT)

    @local_asset_collector = local_asset_collector || S3AssetDeploy::RailsLocalAssetCollector.new
    @remote_asset_collector = S3AssetDeploy::RemoteAssetCollector.new(
      bucket_name,
      s3_client_options: s3_client_options
    )

    @s3_client_options = {
      region: "us-east-1",
      logger: @logger
    }.merge(s3_client_options)
    @upload_asset_options = upload_asset_options
  end

  def upload_asset(asset)
    file_handle = File.open(asset.full_path)

    params = {
      bucket: bucket_name,
      key: asset.path,
      body: file_handle,
      acl: "public-read",
      content_type: asset.mime_type,
      cache_control: "public, max-age=31536000"
    }.merge(@upload_asset_options)

    put_object(params)
  ensure
    file_handle.close
  end

  def local_assets_to_upload
    remote_asset_paths = remote_asset_collector.asset_paths
    local_asset_collector.assets.reject { |asset| remote_asset_paths.include?(asset.path) }
  end

  def upload_assets(dry_run: false)
    verify_no_duplicate_assets!

    local_assets_to_upload.each do |asset|
      next unless File.file?(asset.full_path)
      log "Uploading #{asset.path}..."
      upload_asset(asset) unless dry_run
    end
  end

  # Cleanup old assets on S3. By default it will
  # keep the latest version, 2 backups and any created within the past hour (version_ttl).
  # When assets are removed completely, they are tagged with a removed_at timestamp
  # and eventually deleted based on the removed_ttl.
  def clean_assets(version_limit: 2, version_ttl: 3600, removed_ttl: 172800, dry_run: false)
    verify_no_duplicate_assets!

    version_ttl = version_ttl.to_i
    removed_ttl = removed_ttl.to_i

    log "Cleaning assets from #{bucket_name} S3 bucket. Dry run: #{dry_run}"
    s3_keys_to_delete = []

    unless local_assets_to_upload.empty?
      log "WARNING: Please upload latest asset versions to remote host before cleaning."
      return s3_keys_to_delete
    end

    local_asset_map = local_asset_collector.asset_map
    remote_asset_collector.grouped_assets.each do |original_path, versions|
      current_asset = local_asset_map[original_path]

      # Remove current asset version from the list
      versions_to_delete = versions.reject do |version|
        version.path == current_asset.path if current_asset
      end

      # Sort remaining versions from newest to oldest
      versions_to_delete = versions_to_delete.sort_by(&:last_modified).reverse

      # If the asset has been completely removed from our set of locally compiled assets
      # then use removed_at tag and removed_ttl to determine if it should be deleted from remote host.
      # Otherwise, use version_ttl and version_limit to dermine whether version should be kept.
      versions_to_delete = versions_to_delete.each_with_index.drop_while do |version, index|
        if !current_asset
          obj_tagging = get_object_tagging(version.path)
          tag_set = obj_tagging.tag_set
          removed_at_tag = tag_set.find { |t| t[:key] == "removed_at" }

          if removed_at_tag
            removed_at = Time.parse(removed_at_tag[:value])
            removed_age = Time.now.utc - removed_at
            log "Determining how long ago #{version.path} was removed - removed on #{removed_at} (#{removed_age} seconds ago)"
            removed_age < removed_ttl
          else
            log "Adding removed_at tag to #{version.path}"

            if !dry_run
              put_object_tagging(
                version.path,
                tag_set.push(key: :removed_at, value: Time.now.utc.iso8601)
              )
            end

            true
          end
        else
          # Keep if under age or within the version_limit
          version_age = [0, Time.now - version.last_modified].max
          version_age < version_ttl || index < version_limit
        end
      end.map(&:first)

      s3_keys_to_delete += versions_to_delete.map(&:path)
    end

    if !s3_keys_to_delete.empty? && !dry_run
      delete_objects(s3_keys_to_delete)
    end

    s3_keys_to_delete
  end

  def deploy(clean = true)
    upload_assets
    yield if block_given?
    clean_assets if clean
  end

  def to_s
    "#<#{self.class.name}:#{"0x0000%x" % (object_id << 1)} @bucket_name='#{bucket_name}'>"
  end

  def inspect
    to_s
  end

  protected

  def s3
    @s3 ||= Aws::S3::Client.new(@s3_client_options)
  end

  def verify_no_duplicate_assets!
    if local_asset_collector.original_asset_paths.uniq.length != local_asset_collector.asset_paths.length
      raise S3AssetDeploy::DuplicateAssetsError
    end
  end

  def put_object(object)
    s3.put_object(object)
  end

  def get_object_tagging(key)
    s3.get_object_tagging(bucket: bucket_name, key: key)
  end

  def put_object_tagging(key, tag_set)
    s3.put_object_tagging(bucket: bucket_name, key: key, tagging: { tag_set: tag_set })
  end

  def delete_objects(keys = [])
    s3.delete_objects(
      bucket: bucket_name,
      delete: { objects: keys.map { |key| { key: key }} }
    )
  end

  def log(msg)
    logger.info("#{self.class.name}: #{msg}")
  end
end
