# S3AssetDeploy

This is what we use at [Loomly](https://www.loomly.com) to safely deploy our web assets to S3 to be served via Cloudfront during rolling deploys.
This gem is designed to clean unneeded assets from S3 in a safe manner such that older versions or recently removed assets are kept on S3 during the rolling deploy process. It also maintains a version limit and TTL (time-to-live) on assets to avoid deleting older versions (up to a limit) or those that have been recently removed.

## Why?

At the very beginning, we were serving our assets from our webservers. This isn't ideal for many reasons but one big one is that this is problematic during rolling deploys where you temporarily have some web servers with new assets and some web servers with old assets during the rolling deploy process. When round-robbining requests to instances behind a load balancer this can result in requests for assets hitting web servers that don't have the asset being requested (either the new or the old depending on what web server and what's being requested). We then moved our assets to S3 and began using [asset_sync](https://github.com/AssetSync/asset_sync). We had a lot of problems with `asset_sync`, some of which being:

- It depended on the [fog](https://github.com/fog/fog) gem which was an extra dependency we really didn't need especially since we already had the `aws` gem as a dependency.
- It seemed overly complex, especially around configuration. This likely stems from trying to support so many different storage options and abstractions/configuration options needed for that.
- It didn't have a way to remove outdated or old assets from storage (in this case S3).

As a first pass, we hacked and monkey patched `asset_sync` to work how we wanted and this worked for a while but was overly complicated for what we needed. We then took inspiration from that and wrote our own little library inside our Rails app to work just how we needed. We figured this could be useful to others, so we then moved it to an open source gem. While Rails is a "first-class citizen", this gem can be used with other frameworks by writing your own `S3AssetDeploy::LocalAssetCollector`. See the `Usage` section below for more details.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 's3_asset_deploy'
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
- Upload your assets the S3 bucket you specify
- Yield to the block
- Clean old versions assets or removed assets

Since it's yielding to the block after uploading, but before cleaning, the block is an ideal place to perform a deploy, especially if it's a rolling deploy across multiple servers. If you want to perform an upload or a clean without using `#deploy`, you can call `#upload` or `#clean` directly. For more configuration options, see below.

### Initializing `S3AssetDeploy::Manager`
You'll need to initialize `S3AssetDeploy::Manager` with an S3 bucket name and optionally:

- s3_client_options -> A hash that is passed directly to `[Aws::S3::Client#initialize](https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Client.html#initialize-instance_method)` to configure the S3 client. By default the region is set to `us-east-1`.
- logger -> A custom logger. By default things are logged to `STDOUT`.
- local_asset_collector -> A custom instance of `S3AssetDeploy::LocalAssetCollector`. This allows you to customize how locally compiled assets are collected.
- upload_options -> A hash consisting of options that are passed directly to `[Aws::S3::Client#put_object](https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Client.html#put_object-instance_method)` when each asset is uploaded. By default `acl` is set to `public-read` and `cache_control` is set to `public, max-age=31536000`.

Here's an example:

```ruby
manager = S3AssetDeploy::Manager.new(
  "mybucket",
  s3_client_options: { region: "us-west-1", profile: "my-aws-profile" },
  logger: Logger.new(STDOUT)
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

- version_limit (Integer) -> Max number of older versions of an asset to keep around. Default is `2`
- version_ttl (Integer) -> Number of seconds to keep newly uploaded versions before deleting according to `version_limit`. If a version is still within the `version_ttl`, it will be kept on S3 even if the total number of versions is beyond `version_limit`. Default is `3600`
- removed_ttl (Integer) -> Number of seconds to keep assets on S3 that have been removed from your compiled set of assets. If the age of a removed asset expires according to `removed_ttl`, it will be deleted on the next deploy. Default is `172800`.
- clean (Boolean) -> Skip the clean process during a deploy. Default is `true`.
- dry_run (Boolean) -> Run deploy in read-only mode. This is helpful for debugging purposes and seeing plan of what would happen without performing any writes or deletes. Default is `false`.

`S3AssetDeploy::Manager#deploy` performs its work by delegating to `S3AssetDeploy#upload` and `S3AssetDeploy#clean`, which you can call yourself if you need some more control.


```ruby
manager.upload

manager.clean
```

`S3AssetDeploy::Manager#deploy` and `S3AssetDeploy::Manager#clean` both accept `dry_run` as a keyword argument.
`S3AssetDeploy::Manager#clean` also accepts `version_limit`, `version_ttl`, and `removed_ttl` just like `S3AssetDeploy::Manager#deploy`.


### Customizing local asset collection


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Loomly/s3_asset_deploy. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/Loomly/s3_asset_deploy/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the S3AssetDeploy project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/Loomly/s3_asset_deploy/blob/master/CODE_OF_CONDUCT.md).
