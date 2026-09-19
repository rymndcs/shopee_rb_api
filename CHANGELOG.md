# Changelog

All notable changes to this gem are documented here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and the gem follows Semantic Versioning. Versions stay
`0.x` until the opt-in live tests have recorded real Shopee responses over the documentation fixtures.

## [Unreleased]

### Added

- The first release surface of the shared interface (`CONTRACT.md`, `CONTRACT_VERSION = "1"`): `Client`, `Auth`,
  `Shop`, categories, brands, media, products (including `relist`), stock, prices, read-only orders, webhooks,
  `request`, `Response`, `Pager`, the error tree, `RetryPolicy` and `Transport::NetHttp` (RAC-275).
- Shopee extensions: `auth.exchange_resend_code`, `Grant#merchant_ids`, `variants.init` / `update_tiers` / `list`,
  `categories.variations`, `attributes.search_values`, `logistics_channels`, `warehouses`, `certification_rules`,
  `products.violations` and `products.diagnoses` (RAC-275).
- Every Shopee host as configuration: the `ENDPOINTS` table (`:sg` default, `:cn`, `:br`, `:sandbox`,
  `:sandbox_cn`) plus `base_url:` / `auth_base_url:` for any other host (RAC-275).
- The canonical shared files for the three sibling gems: `CONTRACT.md`, `.rubocop.yml`, `Rakefile`, `Gemfile`,
  `test/support/fake_transport.rb` and the conformance suite in `test/conformance/`, pinned by
  `test/conformance/MANIFEST` and checked by `rake conformance:verify` (RAC-275).
- Opt-in live tests (`rake test:live`) that can record redacted responses into `test/fixtures/` (RAC-275).
- The live recorder never writes an order response (`/api/v2/order/*`) and redacts customer personal-data keys
  (email, phone, name, nickname, username, address, whole recipient and buyer objects) wherever they appear, so no
  customer data can reach a fixture (RAC-275).
- Shared contract version 2 (`CONTRACT_VERSION = "2"`): the conformance suite accepts `Client.new` keywords declared in
  `EXTENSIONS` and an optional `:token` host per `ENDPOINTS` entry with a `token_base_url:` override. Shopee declares
  neither, so its behaviour does not change (RAC-275).
