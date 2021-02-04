# frozen_string_literal: true

require "logger"
require "ostruct"
require "aws-sdk-s3"
require "s3_asset_deploy/rails_local_asset_collector"

class S3AssetDeploy::Manager
  FINGERPRINTED_ASSET_REGEX = /\A(.*)-([[:alnum:]]+)((?:(?:\.[[:alnum:]]+))+)\z/.freeze

  class DuplicateAssetsError < StandardError; end

  attr_reader :bucket_name, :logger, :local_asset_collector

  def initialize(bucket_name, s3_client_options: {}, logger: nil, local_asset_collector: nil)
    @bucket_name = bucket_name
    @logger = logger || Logger.new(STDOUT)
    @local_asset_collector = local_asset_collector || S3AssetDeploy::RailsLocalAssetCollector.new
    @s3_client_options = {
      region: "us-east-1",
      logger: @logger
    }.merge(s3_client_options)
  end

  def remote_assets
    s3.list_objects_v2(bucket: bucket_name).each_with_object([]) do |response, array|
      array.concat(response.contents)
    end
  end

  def remote_asset_paths
    remote_assets.map(&:key)
  end

  def grouped_remote_assets
    remote_assets.map do |asset|
      OpenStruct.new(logical_path: remove_fingerprint(asset.key), asset: asset)
    end.group_by { |asset| asset.logical_path }
  end

  def s3
    @s3 ||= Aws::S3::Client.new(@s3_client_options)
  end

  def local_asset_paths
    local_asset_collector.local_asset_paths
  end

  def local_asset_map
    verify_no_duplicate_assets!

    local_asset_paths.map do |asset|
      [remove_fingerprint(asset), asset]
    end.to_h
  end

  def local_logical_asset_paths
    local_asset_paths.map { |asset| remove_fingerprint(asset) }
  end

  def verify_no_duplicate_assets!
    if local_logical_asset_paths.uniq.length != local_asset_paths.length
      raise DuplicateAssetsError, "Duplicate precompiled assets detected. Please make sure there are no duplicate precompiled assets in the public dir."
    end
  end

  def put_object(object)
    s3.put_object(object)
  end

  # TODO: consider reduced redundancy
  def upload_asset(asset_path)
    file_handle = File.open(local_asset_collector.full_file_path(asset_path))

    asset = {
      bucket: bucket_name,
      key: asset_path,
      body: file_handle,
      acl: "public-read",
      content_type: mime_type_for(asset_path).to_s,
      cache_control: "public, max-age=31536000"
    }

    put_object(asset)
    file_handle.close
  end

  def local_assets_to_upload
    local_asset_paths - remote_asset_paths
  end

  def upload_assets(dry_run: false)
    verify_no_duplicate_assets!

    local_assets_to_upload.each do |asset_path|
      next unless File.file?(local_asset_collector.full_file_path(asset_path))
      log "Uploading #{asset_path}..."
      upload_asset(asset_path) unless dry_run
    end
  end

  # Cleanup old assets on S3. By default it will
  # keep the latest version, 2 backups and any created within the past hour.
  def clean_assets(count: 2, age: 3600, dry_run: false)
    verify_no_duplicate_assets!

    log "Cleaning assets from #{bucket_name} S3 bucket"
    assets_to_delete = []

    unless local_assets_to_upload.empty?
      log "WARNING: Please upload latest asset versions to remote host before cleaning."
      return assets_to_delete
    end

    grouped_remote_assets.each do |logical_path, versions|
      current_fingerprinted_path = local_asset_map[logical_path]

      versions.reject do |version|
        # Remove current asset versions from the list
        version.asset.key == current_fingerprinted_path
      end.sort_by do |version|
        version.asset.last_modified
      end.reverse.each_with_index.drop_while do |version, index|
        version_age = [0, Time.now - version.asset.last_modified].max

        # If the asset has been completely removed from our set of assets
        # then use only age to determine if it should be deleted from remote host.
        # Otherwise, use age and count to dermine whether version should be kept.
        unless current_fingerprinted_path
          version_age < age
        else
          # Keep if under age or within the count limit
          version_age < age || index < count
        end
      end.each do |version, index|
        assets_to_delete << version.asset.key
      end
    end

    if !assets_to_delete.empty? && !dry_run
      s3.delete_objects(
        bucket: bucket_name,
        delete: {
          objects: assets_to_delete.map { |asset| { key: asset } }
        }
      )
    end

    assets_to_delete
  end

  def sync(clean = true)
    upload_assets
    yield if block_given?
    clean_assets if clean
  end

  def remove_fingerprint(asset_path)
    match_data = asset_path.match(FINGERPRINTED_ASSET_REGEX)

    unless match_data
      log "WARNING: No fingerprint found for #{asset_path}!"
      return asset_path
    end

    "#{match_data[1]}#{match_data[3]}"
  end

  def mime_type_for(asset)
    extension = File.extname(asset)[1..-1]
    return "application/json" if extension == "map"
    MIME::Types.type_for(extension).first
  end

  def log(msg)
    logger.info("AssetSyncService: #{msg}")
  end
end
