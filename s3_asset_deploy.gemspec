# frozen_string_literal: true

require_relative "lib/s3_asset_deploy/version"

Gem::Specification.new do |spec|
  spec.name          = "s3_asset_deploy"
  spec.version       = S3AssetDeploy::VERSION
  spec.authors       = ["Loomly"]
  spec.email         = ["contact@loomly.com"]

  spec.summary       = "Deploy & manage static assets on S3 with rolling deploys & rollbacks in mind."
  spec.homepage      = "https://github.com/Loomly/s3_asset_deploy"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.4.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/Loomly/s3_asset_deploy"
  spec.metadata["changelog_uri"] = "https://github.com/Loomly/s3_asset_deploy/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "aws-sdk-s3", "~> 1.0"
  spec.add_dependency "mime-types", "~> 3.0"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "timecop", "~> 0.9"
  spec.add_development_dependency "pry", "~> 0.13"
  spec.add_development_dependency "pry-byebug", "~> 3.9"
  spec.add_development_dependency "rspec_junit_formatter", "~> 0.4"

  # Required for aws-sdk-ruby.
  # See https://github.com/aws/aws-sdk-ruby/blob/version-3/gems/aws-sdk-core/lib/aws-sdk-core/xml/parser.rb#L74
  spec.add_development_dependency "nokogiri", "~> 1.13"

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html
end
