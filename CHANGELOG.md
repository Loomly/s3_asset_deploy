# Changelog

## [v1.0.2](https://github.com/Loomly/s3_asset_deploy/compare/v1.0.1...v1.0.2) - 2022-09-12
- Remove `acl` specification when saving removal manifest. Bucket policies should be used instead.

## [v1.0.1](https://github.com/Loomly/s3_asset_deploy/compare/v1.0.0...v1.0.1) - 2022-02-23
- Batch delete API calls with max 1000 keys - [PR #32](https://github.com/Loomly/s3_asset_deploy/pull/32)

## [v1.0.0](https://github.com/Loomly/s3_asset_deploy/compare/v0.1.1...v1.0.0) - 2021-05-13
### Breaking Changes
- Remove default `acl` setting when uploading assets to bucket - [PR #25](https://github.com/Loomly/s3_asset_deploy/pull/25)

## [v0.1.1](https://github.com/Loomly/s3_asset_deploy/compare/v0.1.0...v0.1.1) - 2021-03-22
- Fix bug in AssetHelper.remove_fingerprint referencing asset_path - [4f370ad](https://github.com/Loomly/s3_asset_deploy/commit/4f370ad9c0c1c274acb9b1d8585b878f47020277)
