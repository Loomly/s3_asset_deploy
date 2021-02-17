# frozen_string_literal: true

class S3AssetDeploy::Error < StandardError
end

class S3AssetDeploy::DuplicateAssetsError < S3AssetDeploy::Error
  def initialize(msg = "Duplicate precompiled assets detected. Please make sure there are no duplicate precompiled assets in the public dir.")
    super
  end
end
