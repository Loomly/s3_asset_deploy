# S3AssetDeploy

[![CircleCI](https://circleci.com/gh/Loomly/s3_asset_deploy.svg?style=shield)](https://circleci.com/gh/Loomly/s3_asset_deploy)
[![Gem Version](https://badge.fury.io/rb/s3_asset_deploy.svg)](https://badge.fury.io/rb/s3_asset_deploy)

During rolling deploys to our web instances, this is what we use at
[Loomly](https://www.loomly.com) to safely deploy our web assets to S3 to be served via Cloudfront.
This gem is designed to upload and clean unneeded assets from S3 in a safe manner such that older
versions or recently removed assets are kept on S3 during the rolling deploy process.
It also maintains a version limit and TTL (time-to-live) on assets to avoid deleting
recent and outdated versions (up to a limit) or those that have been recently removed.

## Background

At the very beginning, we were serving our assets from our webservers. This isn't ideal for many reasons, but one big one is that it's problematic during rolling deploys where you temporarily have some web servers with new assets and some with old assets during the deploy. When round-robbining requests to instances behind a load balancer, this can result in requests for assets hitting web servers that don't have the asset being requested (either the new or the old depending on what web server and what's being requested). One way to fix this problem is to serve your assets from a CDN and keep both old and new versions of assets available on the CDN during the deploy process. So we decided to serve our assets from Cloudfront, backed by S3. In order to upload our assets to S3 during our deploy process, we started using [`asset_sync`](https://github.com/AssetSync/asset_sync). `asset_sync` served us well for quite some time, but our needs started to diverge a bit. Namely, `asset_sync`:

- Depends on the [`fog`](https://github.com/fog/fog) gem which was an extra dependency we didn't need since we already had the [`aws-sdk-s3`](https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3.html) gem as a dependency.
- Uses a global configuration, which made it difficult to deploy to different S3 buckets depending on the environment (development, staging, production, etc.).
- Didn't have a way to remove or retire outdated or old assets from storage (in this case S3).

We took inspiration from `asset_sync` and ended up writing our own library inside our Rails app. We figured this could be useful to others, so we then moved it to an open source gem. While Rails is a "first-class citizen", this gem can be used with other frameworks by writing your own `S3AssetDeploy::LocalAssetCollector`. See the `Usage` section below for more details.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "s3_asset_deploy"
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install s3_asset_deploy

## Usage

Before using `S3AssetDeploy` you want to make sure to compile your assets. Assets must also be compiled using [fingerprinting](https://guides.rubyonrails.org/asset_pipeline.html#what-is-fingerprinting-and-why-should-i-care-questionmark) for things to work correctly. By default, `S3AssetDeploy` works with Rails and will find your locally compiled assets after running `rake assets:precompile`. Once you've compiled your assets, you can deploy them with:


```ruby
manager = S3AssetDeploy::Manager("my-s3-bucket")
manager.deploy do
  # Perform deploy to web instances in this block
end
```

`S3AssetDeploy::Manager#deploy` will perform the following steps:
- Upload your assets to the S3 bucket you specify
- Yield to the block
- Clean old versions assets or removed assets

Since it's yielding to the block after uploading, but before cleaning, the block is an ideal place to perform a deploy, especially if it's a rolling deploy across multiple servers. If you want to perform an upload or a clean without using `#deploy`, you can call `#upload` or `#clean` directly. For more configuration options, see below.

### Initializing [`S3AssetDeploy::Manager`](https://github.com/Loomly/s3_asset_deploy/blob/main/lib/s3_asset_deploy/manager.rb)
You'll need to initialize `S3AssetDeploy::Manager` with an S3 bucket name and **optionally**:

- **s3_client_options** (Hash) -> A hash that is passed directly to [`Aws::S3::Client#initialize`](https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Client.html#initialize-instance_method) to configure the S3 client. By default the region is set to `us-east-1`.
- **logger** (Logger) -> A custom logger. By default things are logged to `STDOUT`.
- **local_asset_collector** (S3AssetDeploy::LocalAssetCollector) -> A custom instance of `S3AssetDeploy::LocalAssetCollector`. This allows you to customize how locally compiled assets are collected.
- **upload_options** (Hash) -> A hash consisting of options that are passed directly to [`Aws::S3::Client#put_object`](https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Client.html#put_object-instance_method) when each asset is uploaded. By default `cache_control` is set to `public, max-age=31536000`.
- **remove_fingerprint** (Lambda) -> Lambda for overriding how fingerprints are removed from asset paths. Fingerprints need to be removed during the cleaning process in order to group versions of the same file. If no Lambda is provided, [`S3AssetDeploy::AssetHelper.remove_fingerprint`](https://github.com/Loomly/s3_asset_deploy/blob/main/lib/s3_asset_deploy/asset_helper.rb#L8) is used by default.

Here's an example:

```ruby
manager = S3AssetDeploy::Manager.new(
  "mybucket",
  s3_client_options: { region: "us-west-1", profile: "my-aws-profile" },
  logger: Logger.new(STDOUT),
  remove_fingerprint: ->(path) { path.gsub("-myfingerprint", "") }
)
```

### Deploying Assets
Once you have an instance of `S3AssetDeploy::Manager`, you can deploy your precompiled assets with `S3AssetDeploy::Manager#deploy`:

```ruby
manager.deploy(version_limit: 2, version_ttl: 3600, removed_ttl: 172800) do
  # Perform deploy to web instances in this block
end
```

This will upload new assets and perform a clean, which deletes removed assets and old versions from your bucket after the block is executed.
With the arguments used above, the clean process will keep the latest version on S3, two of the most recent older versions (`version_limit`), and any versions created within the last hour (`version_ttl`).
If you there are assets that are in your S3 bucket but no longer included in your locally compiled bundle, they will be deleted from S3 using the `removed_ttl` (after two days in the case above). This process uses [S3 object tagging](https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Client.html#put_object_tagging-instance_method) to track `removed_at` timestamps. Here are a list of all the options you can pass to `#deploy`:

- **version_limit** (Integer) -> Max number of older versions of an asset to keep around. Note that this limit does **not** include the current version. Therefore, setting this to 0 will keep the current version and delete any older versions. Default is `2`.
- **version_ttl** (Integer) -> Number of seconds to keep newly uploaded versions before deleting according to `version_limit`. If an older version is still within the `version_ttl`, it will be kept on S3 even if the total number of older versions is beyond `version_limit`. Default is `3600`.
- **removed_ttl** (Integer) -> Number of seconds to keep assets on S3 that have been removed from your compiled set of assets. If the age of a removed asset expires according to `removed_ttl`, it will be deleted on the next deploy. Default is `172800`.
- **clean** (Boolean) -> Skip the clean process during a deploy. Default is `true`.
- **dry_run** (Boolean) -> Run deploy in read-only mode. This is helpful for debugging purposes and seeing plan of what would happen without performing any writes or deletes. Default is `false`.

`S3AssetDeploy::Manager#deploy` performs its work by delegating to `S3AssetDeploy#upload` and `S3AssetDeploy#clean`, which you can call yourself if you need some more control.


```ruby
# Upload new assets
manager.upload

# Delete old versions and removed assets from S3
manager.clean
```

`S3AssetDeploy::Manager#deploy` and `S3AssetDeploy::Manager#clean` both accept `dry_run` as a keyword argument.
`S3AssetDeploy::Manager#clean` also accepts `version_limit`, `version_ttl`, and `removed_ttl` just like `S3AssetDeploy::Manager#deploy`.

### Practical Example of Usage
There are many ways to use and invoke `S3AssetDeploy`. How you use it will depend on your deploy process and pipeline. At Loomly, we have some rake tasks that are invoked from our CI/CD pipeline to perform deploys.
Here's a basic example of how we use `S3AssetDeploy`:


```ruby
# lib/tasks/deploy.rake

require "s3_asset_deploy"

namespace :deploy do
  task precompile: :environment do
    puts "Precompiling assets..."
    sh("RAILS_ENV=production SECRET_KEY_BASE='secret key' bundle exec rake assets:precompile")
  end

  task clobber_assets: :environment do
    puts "Clobbering assets..."
    sh("RAILS_ENV=production SECRET_KEY_BASE='secret key' bundle exec rake assets:clobber")
  end

  task :production do
    Rake::Task["deploy:precompile"].invoke

    manager = S3AssetDeploy::Manager("my-s3-bucket")
    manager.deploy do
      # Perform deploy to web instances in this block.
      # How you do this will depend on where you are hosting your application and what tools you use to deploy.
    end

    Rake::Task["deploy:clobber_assets"].invoke # <-- if you are running on CI where the precompiled assets dir is ephemeral, this may be unnecessary
  end
end
```

Given the example above, we can perform a deploy by running `bundle exec rake deploy:production`. This task will:
1. Precompile assets
2. Upload any new assets to S3 using `S3AssetDeploy`
3. Deploy a new version of our application
4. Clean any outdated or unused assets from S3 using `S3AssetDeploy`

## Customizing local asset collection
By default, `S3AssetDeploy::Manager` will use [`S3AssetDeploy::RailsLocalAssetCollector`](https://github.com/Loomly/s3_asset_deploy/blob/main/lib/s3_asset_deploy/rails_local_asset_collector.rb) to collect locally compiled assets. This will use the `Sprockets::Manifest` and `Webpacker` config (if `Webpacker` is installed) to locate the compiled assets. `S3AssetDeploy::RailsLocalAssetCollector` inherits from the [`S3AssetDeploy::LocalAssetCollector`](https://github.com/Loomly/s3_asset_deploy/blob/main/lib/s3_asset_deploy/local_asset_collector.rb) base class. You can completely customize how your local assets are collected for deploys by creating your own class that inherits from `S3AssetDeploy::LocalAssetCollector` and passing it into the manager. You'll want override `S3AssetDeploy::LocalAssetCollector#assets` in your custom collector such that it returns an array of `S3AssetDeploy::LocalAsset` instances. Here's a basic example:


```ruby
class MyCustomLocalAssetCollector < S3AssetDeploy::LocalAssetCollector
  def assets
    # Override this method to return an array of your locally compiled assets
    # as instances of S3AssetDeploy::LocalAsset
    [S3AssetDeploy::LocalAsset.new("path-to-my-asset.jpg")]
  end
end

manager = S3AssetDeploy::Manager.new(
  "mybucket",
  local_asset_collector: MyCustomLocalAssetCollector.new
)
```

## Dry run
As mentioned above, you can run operations in "dry" mode by passing `dry_run: true`.
This will skip any write or delete operations and only perform read opeartions with log output.
This is helpful for debugging or planning purposes.

```ruby
> manager = S3AssetDeploy::Manager("my-s3-bucket")
> manager.deploy(dry_run: true)

I, [2021-02-17T16:12:23.703677 #65335]  INFO -- : S3AssetDeploy::Manager: Cleaning assets from test-bucket S3 bucket. Dry run: true
I, [2021-02-17T16:12:23.703677 #65335]  INFO -- : S3AssetDeploy::Manager: Determining how long ago assets/file-2-34567.jpg was removed - removed on 2021-02-15 23:12:22 UTC (172801.703677 seconds ago)
I, [2021-02-17T16:12:23.703677 #65335]  INFO -- : S3AssetDeploy::Manager: Determining how long ago assets/file-3-9876666.jpg was removed - removed on 2021-02-15 23:12:24 UTC (172799.703677 seconds ago)
```

## AWS IAM Permissions
`S3AsetDeploy` requires the following AWS IAM permissions to list, put, and delete objects in your S3 Bucket:

```json
"Statement": [
  {
    "Action": [
      "s3:ListBucket",
      "s3:PutObject*",
      "s3:DeleteObject"
    ],
    "Effect": "Allow",
    "Resource": [
      "arn:aws:s3:::#{YOUR_BUCKET}",
      "arn:aws:s3:::#{YOUR_BUCKET}/*"
    ]
  }
]
```

## Configuration with Cloudfront

### Restricting Access with Origin Access Identity
If you want to setup Cloudfront to serve your assets, you can [restrict access to the bucket by using an Origin Access Identity](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html#private-content-granting-permissions-to-oai) so that only Cloudfront can access the objects in your bucket.

If you do this, your bucket policy will look something like this:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowGetObject",
            "Effect": "Allow",
            "Principal": {
                "AWS": [
                  "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity #{YOUR_OAI_ID}"
                ]
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::#{YOUR_BUCKET}/*"
        },
        {
            "Sid": "DenyGetObject",
            "Effect": "Deny",
            "Principal": {
                "AWS": "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity #{YOUR_OAI_ID}"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::#{YOUR_BUCKET}/s3-asset-deploy-removal-manifest.json"
        }
    ]
}
```

This policy allows Cloudfront to access everything **except** the removal manifest uploaded and maintained by this gem since this manifest does not need to be served to clients.

### CORS
Your CORS configuration on the bucket might look something like this:

```json
[
    {
        "AllowedHeaders": [
            "Authorization"
        ],
        "AllowedMethods": [
            "GET",
            "HEAD"
        ],
        "AllowedOrigins": [
            "https://*.#{YOUR_SITE}.com"
        ],
        "ExposeHeaders": [],
        "MaxAgeSeconds": 3000
    }
]
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bundle exec rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Loomly/s3_asset_deploy. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/Loomly/s3_asset_deploy/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the S3AssetDeploy project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/Loomly/s3_asset_deploy/blob/main/CODE_OF_CONDUCT.md).
