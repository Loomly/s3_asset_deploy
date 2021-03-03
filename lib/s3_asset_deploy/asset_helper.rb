# frozen_string_literal: true

require "mime/types"

class S3AssetDeploy::AssetHelper
  FINGERPRINTED_ASSET_REGEX = /\A(.*)-([[:alnum:]]+)((?:(?:\.[[:alnum:]]+))+)\z/.freeze

  def self.remove_fingerprint(path)
    match_data = path.match(FINGERPRINTED_ASSET_REGEX)
    return path unless match_data
    "#{match_data[1]}#{match_data[3]}"
  end

  def self.mime_type_for_path(path)
    extension = File.extname(path)[1..-1]
    return "application/json" if extension == "map"
    MIME::Types.type_for(extension).first
  end
end
