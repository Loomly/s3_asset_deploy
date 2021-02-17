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

TODO: Write usage instructions here

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Loomly/s3_asset_deploy. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/Loomly/s3_asset_deploy/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the S3AssetDeploy project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/Loomly/s3_asset_deploy/blob/master/CODE_OF_CONDUCT.md).
