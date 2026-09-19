# shopee_rb_api

A Ruby client for the [Shopee Open Platform API v2](https://open.shopee.com/developer-guide/16): signed requests,
seller authorization and tokens, catalogue, products, stock, prices, read-only orders, and push (webhook)
verification. No runtime dependencies: `net/http`, `openssl` and `json` from the standard library.

It is a library. It implements Shopee faithfully and configurably and leaves every deployment decision to you: which
host, which sandbox, when to refresh or ask a seller to re-consent, and how to store tokens.

It is one of three sibling gems (`shopee_rb_api`, `lazada_rb_api`, `tiktok_shop_rb_api`) that share one interface,
written down in [CONTRACT.md](CONTRACT.md). Code written against one of them reads the same against the others.

Status: `0.x`. The response fixtures come from Shopee's documentation samples; the version stays below 1.0 until the
opt-in live tests (see Testing) have recorded real responses over them.

## Installation

The gem is not published to RubyGems. Pin it by git tag:

```ruby
# Gemfile
gem "shopee_rb_api", git: "https://github.com/rymndcs/shopee_rb_api.git", tag: "v0.1.0"
```

Ruby 3.3 or newer.

## Configuration

One `Client` per Shopee app. There is no global configuration; the client is immutable and thread-safe.

```ruby
require "shopee_rb_api"

client = ShopeeRbApi::Client.new(
  app_key: ENV.fetch("SHOPEE_PARTNER_ID"),     # Shopee partner_id
  app_secret: ENV.fetch("SHOPEE_PARTNER_KEY"), # Shopee partner_key
  endpoint: :sg,                               # default; see the table below
  transport: ShopeeRbApi::Transport::NetHttp.new(open_timeout: 5, read_timeout: 30),
  clock: -> { Time.now },
  logger: Rails.logger,                        # debug lines only; never a secret
  retry_policy: ShopeeRbApi::RetryPolicy.none  # the default: the gem never retries on its own
)
```

Hosts are configuration, not code. `endpoint:` picks both the API host and the seller authorization page host from
`ShopeeRbApi::ENDPOINTS`:

| `endpoint:` | API host | Authorization page host | Use when |
|---|---|---|---|
| `:sg` (default) | `https://partner.shopeemobile.com` | `https://open.shopee.com` | your server runs near Singapore |
| `:cn` | `https://openplatform.shopee.cn` | `https://open.shopee.cn` | your server runs near Mainland China |
| `:br` | `https://openplatform.shopee.com.br` | `https://open.shopee.com.br` | your server runs near the US |
| `:sandbox` | `https://openplatform.sandbox.test-stable.shopee.sg` | `https://open.sandbox.test-stable.shopee.com` | sandbox, all developers |
| `:sandbox_cn` | `https://openplatform.sandbox.test-stable.shopee.cn` | `https://open.sandbox.test-stable.shopee.cn` | sandbox, Mainland China |

Shopee chooses the API host by where **your server** runs, not by the shop's market: Philippine and Malaysian shops
share one host. For any other host (a proxy, the Brazil sandbox consent page, a host Shopee adds later) pass a URL:

```ruby
ShopeeRbApi::Client.new(app_key: id, app_secret: key, endpoint: :sandbox,
                        base_url: "https://shopee-egress.internal",                # API host
                        auth_base_url: "https://open.sandbox.test-stable.shopee.com.br") # authorization page host
```

Before the first call, declare your server's IP addresses and the redirect URL domains in the Shopee console;
Shopee refuses undeclared ones (`source_ip_undeclared`).

## Authorization

The gem stores no tokens and never refreshes on its own. Access tokens live 4 hours; a refresh token lives 30 days
and is **single use**, so persist both tokens of every `Grant` in one write before doing anything else.

```ruby
# 1. Send the seller to the authorization page.
url = client.auth.authorize_url(redirect_uri: "https://app.example/shopee/callback", state: csrf_token)

# 2. Shopee redirects back with code and shop_id (shop account) or main_account_id (main account).
grant = client.auth.exchange_code(code: params[:code], shop_id: params[:shop_id])
grant.access_token; grant.refresh_token
grant.access_token_expires_at   # absolute UTC Time, from expire_in and the injected clock
grant.refresh_token_expires_at  # nil: Shopee documents 30 days but returns no field for it
grant.shop_ids                  # ["14701711"]; a main account lists every shop it authorized
grant.merchant_ids              # extension: main-account grants

# 3. Refresh before the access token expires. Exactly one of shop_id: or merchant_id:.
grant = client.auth.refresh(refresh_token: stored.refresh_token, shop_id: 14701711)

# Lost the latest tokens? Use the single-use resend code from the console (live environment only).
grant = client.auth.exchange_resend_code(resend_code: "resend5a4d...")

# Every shop authorized to the app, with the seller-chosen authorization deadline (at most 365 days).
client.authorized_shops.each do |ref|
  ref.shop_id; ref.region; ref.authorization_expires_at; ref.locator  # => { shop_id: "14701711" }
end
```

## Shop session (locator)

```ruby
shop = client.shop(access_token: stored.access_token, shop_id: 14701711)
shop.locator  # => { shop_id: "14701711" }; ShopeeRbApi::Shop::LOCATOR_KEYS == [:shop_id]
```

`shop_id` is sent and signed on every Shop-type call. `AuthorizedShop#locator` gives you the Hash to splat in.

## Capabilities

Every method makes exactly one request (iterating a `Pager` makes one per page). Identity arguments (`product_id`,
`category_id`, `order_id`, `seller_sku`, `title`) accept a String or an Integer; everything else is Shopee's own
field names, passed through untouched. Non-paged methods return a `ShopeeRbApi::Response`.

| Capability | Example | Shopee endpoint |
|---|---|---|
| Shop info | `shop.info.data["expire_time"]` | [`get_shop_info`](https://open.shopee.com/documents/v2/v2.shop.get_shop_info?module=92&type=1) |
| Listing limits | `shop.limits(category_id: 102301).data["item_count_limit"]` | [`get_item_limit`](https://open.shopee.com/documents/v2/v2.product.get_item_limit?module=89&type=1) |
| Category tree | `shop.categories.list(language: "en").data["category_list"]` | [`get_category`](https://open.shopee.com/documents/v2/v2.product.get_category?module=89&type=1) |
| Category attributes | `shop.categories.attributes(102301, language: "en")` | [`get_attribute_tree`](https://open.shopee.com/documents/v2/v2.product.get_attribute_tree?module=89&type=1) |
| Category suggestion | `shop.categories.recommend(title: "Bosch H4 bulb").data["category_id"]` | [`category_recommend`](https://open.shopee.com/documents/v2/v2.product.category_recommend?module=89&type=1) |
| Brands | `shop.brands.list(category_id: 102301, status: 1).each { \|b\| b["brand_id"] }` | [`get_brand_list`](https://open.shopee.com/documents/v2/v2.product.get_brand_list?module=89&type=1) |
| Image upload | `shop.media.upload_image(File.open("bulb.jpg"), scene: "normal").data["image_info"]["image_id"]` | [`media_space/upload_image`](https://open.shopee.com/documents/v2/v2.media_space.upload_image?module=91&type=1) |
| Create product | `shop.products.create({ item_name: "...", description: "...", original_price: 638, weight: 0.2, category_id: 102301, image: { image_id_list: [id] }, logistic_info: [{ logistic_id: 80101, enabled: true }] })` | [`add_item`](https://open.shopee.com/documents/v2/v2.product.add_item?module=89&type=1) |
| Get product | `shop.products.get(34002).data["item_list"].first["item_status"]` | [`get_item_base_info`](https://open.shopee.com/documents/v2/v2.product.get_item_base_info?module=89&type=1) |
| Update product (partial) | `shop.products.update(34002, { attribute_list: [...] })` | [`update_item`](https://open.shopee.com/documents/v2/v2.product.update_item?module=89&type=1) |
| List products | `shop.products.list(item_status: ["NORMAL"]).each { \|item\| item["item_id"] }` | [`get_item_list`](https://open.shopee.com/documents/v2/v2.product.get_item_list?module=89&type=1) |
| Find by seller SKU | `shop.products.find_by_seller_sku("OT405") # => ["34002"]` (item-level SKU only) | [`search_item`](https://open.shopee.com/documents/v2/v2.product.search_item?module=89&type=1) |
| Unlist | `shop.products.unlist([34002, 34003]).item_errors` (≤ `Products::UNLIST_BATCH_MAX` = 50) | [`unlist_item`](https://open.shopee.com/documents/v2/v2.product.unlist_item?module=89&type=1) |
| Relist | `shop.products.relist([34002]).item_errors` (≤ `Products::RELIST_BATCH_MAX` = 50) | [`unlist_item`](https://open.shopee.com/documents/v2/v2.product.unlist_item?module=89&type=1) with `unlist: false` |
| Get stock | `shop.stock.get(34002).data["model"].map { \|m\| m["stock_info_v2"] }` | [`get_model_list`](https://open.shopee.com/documents/v2/v2.product.get_model_list?module=89&type=1) |
| Update stock | `shop.stock.update(34002, [{ model_id: 0, seller_stock: [{ location_id: "PHZ", stock: 10 }] }])` | [`update_stock`](https://open.shopee.com/documents/v2/v2.product.update_stock?module=89&type=1) |
| Update prices | `shop.prices.update(34002, [{ model_id: 0, original_price: 638 }])` | [`update_price`](https://open.shopee.com/documents/v2/v2.product.update_price?module=89&type=1) |
| List orders (read-only) | `shop.orders.list(time_range_field: "update_time", time_from: t0, time_to: t1).each { \|o\| o["order_sn"] }` | [`get_order_list`](https://open.shopee.com/documents/v2/v2.order.get_order_list?module=94&type=1) |
| Get order (read-only) | `shop.orders.get("201218V2Y6E59M", response_optional_fields: "item_list")` | [`get_order_detail`](https://open.shopee.com/documents/v2/v2.order.get_order_detail?module=94&type=1) |

**Shopee extensions** (declared in `ShopeeRbApi::EXTENSIONS`; no sibling gem has them in this shape):

| Extension | Example | Shopee endpoint |
|---|---|---|
| Lost-token recovery | `client.auth.exchange_resend_code(resend_code: code)` | [`get_token_by_resend_code`](https://open.shopee.com/documents/v2/v2.public.get_token_by_resend_code?module=104&type=1) |
| Set up variants | `shop.variants.init(34002, { standardise_tier_variation: [...], model: [...] })` | [`init_tier_variation`](https://open.shopee.com/documents/v2/v2.product.init_tier_variation?module=89&type=1) |
| Re-tier without breaking models | `shop.variants.update_tiers(34002, { standardise_tier_variation: [...], model_list: [...] })` | [`update_tier_variation`](https://open.shopee.com/documents/v2/v2.product.update_tier_variation?module=89&type=1) |
| List models | `shop.variants.list(34002).data["model"]` | [`get_model_list`](https://open.shopee.com/documents/v2/v2.product.get_model_list?module=89&type=1) |
| Standard variation vocabulary | `shop.categories.variations(102301).data["standardise_variation_list"]` | [`get_variations`](https://open.shopee.com/documents/v2/v2.product.get_variations?module=89&type=1) (served at `get_variation_tree`) |
| Search attribute values | `shop.attributes.search_values(attribute_id: 101777, value_name: "H4").first(20)` | [`search_attribute_value_list`](https://open.shopee.com/documents/v2/v2.product.search_attribute_value_list?module=89&type=1) |
| Logistics channels | `shop.logistics_channels.data["logistics_channel_list"]` | [`get_channel_list`](https://open.shopee.com/documents/v2/v2.logistics.get_channel_list?module=95&type=1) |
| Warehouses | `shop.warehouses.data.map { \|w\| w["location_id"] }` | [`get_warehouse_detail`](https://open.shopee.com/documents/v2/v2.shop.get_warehouse_detail?module=92&type=1) |
| Certification rules | `shop.certification_rules(category_id: 102301, attribute_list: [...])` | [`get_product_certification_rule`](https://open.shopee.com/documents/v2/v2.product.get_product_certification_rule?module=89&type=1) |
| Violations | `shop.products.violations([34002]).data["item_list"]` (≤ 50 ids) | [`get_item_violation_info`](https://open.shopee.com/documents/v2/v2.product.get_item_violation_info?module=89&type=1) |
| Content diagnosis | `shop.products.diagnoses([34002]).data["success_item_list"]` (≤ 48 ids) | [`get_item_content_diagnosis_result`](https://open.shopee.com/documents/v2/v2.product.get_item_content_diagnosis_result?module=89&type=1) |

Shopee facts worth knowing before you publish:

- `add_item` creates the item **without** variants. Wait at least 5 seconds before `variants.init`; the gem never
  sleeps. `variants.init` on an item that already has tiers replaces the structure and invalidates every `model_id`.
- Prices are in major units of the shop's currency. Philippine shops accept integer prices only.
- Weight is kilograms (float); package dimensions are whole centimetres.
- `get_order_list` windows are at most 15 days; a longer window raises `ArgumentError`. Step the window yourself.
- GET list parameters you pass (for example `item_status: %w[NORMAL UNLIST]`) are sent as repeated query keys, as
  `get_item_list` documents.
- Shopee documents `expire_in` as seconds; one documentation sample shows an epoch-sized value. The gem follows the
  field description.

### Response

```ruby
res = shop.products.unlist([34002, 34003])
res.data         # the payload with Shopee's envelope removed, frozen, never coerced
res.request_id   # Shopee's request_id
res.warnings     # ["..."] when Shopee reports a degraded success
res.item_errors  # [#<data ItemError id="34003", code="", message="Can't unlist item when item is under promotion">]
res.http_status; res.endpoint; res.raw
```

Shopee's payload sits under `response` on most endpoints, under `data` on `get_variation_tree`, and at the top level
on the token, public and `get_shop_info` endpoints. `data` hides that difference; `raw` keeps the body as received.

## Pagination

```ruby
pager = shop.products.list(item_status: ["NORMAL"], page_size: 50)
pager.each { |item| ... }               # every item, fetching pages lazily
pager.lazy.first(10)                    # only as many requests as needed
pager.each_page { |page| page.items; page.next_cursor; page.total }
page = pager.first_page
shop.products.list(item_status: ["NORMAL"], cursor: page.next_cursor)  # resume later
```

`next_cursor` is an opaque String: store it, pass it back, never parse it. `page_size:` defaults to Shopee's maximum
(100) and raises `ArgumentError` above it. `attributes.search_values` takes Shopee's own `limit:` and `cursor:`.

## Errors and retries

Every failure raises a subclass of `ShopeeRbApi::Error`; see [CONTRACT.md §8](CONTRACT.md) for the tree. Shopee
signals errors in the body (`error` is not empty), whatever the HTTP status. The class comes from Shopee's
`(error, message)` pair, because Shopee overloads codes: `error_auth` also carries business rejections such as
holiday mode, and `error_param` also carries signature failures. A code the table does not know raises plain
`ApiError`.

```ruby
begin
  shop.products.update(34002, payload)
rescue ShopeeRbApi::AuthenticationError
  # refresh (once, persisting both tokens) or ask the seller to re-authorize
rescue ShopeeRbApi::QuotaExceededError => e
  e.retry_after  # seconds until 00:00 UTC+8, when the app-wide daily quota resets
rescue ShopeeRbApi::ApiError => e
  e.code; e.message; e.request_id; e.retryable?
end
```

Retries are off by default. Opt in with a policy; it retries only `retryable?` errors (rate limits, and server or
network errors on idempotent calls) and re-signs every attempt:

```ruby
ShopeeRbApi::Client.new(..., retry_policy: ShopeeRbApi::RetryPolicy.new(max_retries: 5))
```

Shopee has no idempotency key, so `products.create`, `products.update`, `media.upload_image` and the variant calls are
never retried: after a timeout, look the item up (for example `find_by_seller_sku`) before trying again.

## Webhooks

Shopee signs each push with `HMAC-SHA256(partner_key, callback_url + "|" + raw_body)` in the `Authorization` header.

```ruby
event = client.verify_webhook(raw_body: request.raw_post,
                              signature: request.headers["Authorization"],
                              url: "https://app.example/shopee/push")  # the URL registered in the console
event.type         # :authorization_expiring (code 12, 7 days ahead) | :deauthorized (code 2) | :other
event.code         # "12", "3", ...
event.shop_id; event.occurred_at; event.data
```

- `url:` must be the exact callback URL registered in the Shopee console. Behind a proxy that is not always
  `request.original_url`.
- Verify the raw body as received; never re-serialize parsed JSON.
- Reply **2xx with an empty body**. Anything else counts as a failed push; below a 30% success rate over more than
  600 pushes in 6 hours, Shopee disables the subscription.
- `ShopeeRbApi::Webhook.verify(...)` and `.parse(raw_body)` are the pure functions underneath.

## Raw requests

Any endpoint the gem does not wrap, signed, parsed and classified the same way:

```ruby
client.request(:get, "/api/v2/public/get_shops_by_partner", query: { page_no: 1 })          # partner-signed
shop.request(:post, "/api/v2/product/delete_item", body: { item_id: 34002 }, idempotent: false) # shop-signed
```

## Testing

```sh
bundle install
bundle exec rake          # unit tests, the conformance suite, RuboCop and conformance:verify
```

The default suite makes no network call. It runs every request through `FakeTransport` against fixtures in
`test/fixtures/`; each fixture names its source in `_source` (the documentation page and pull date, or
"recorded live <date>").

The opt-in live tests only read, never refresh a token and never write:

```sh
SHOPEE_SANDBOX_PARTNER_ID=... SHOPEE_SANDBOX_PARTNER_KEY=... \
SHOPEE_SANDBOX_SHOP_ID=... SHOPEE_SANDBOX_ACCESS_TOKEN=... bundle exec rake test:live
```

Use `SHOPEE_LIVE_*` for the production app (endpoint `:sg` unless `SHOPEE_LIVE_ENDPOINT` says otherwise). Add
`SHOPEE_RECORD=1` to replace the documentation fixtures with redacted recordings.

## Contract version

`ShopeeRbApi::CONTRACT_VERSION` is `"1"`. The shared interface lives in [CONTRACT.md](CONTRACT.md), which is identical
in all three sibling gems; `test/conformance/` enforces it and `rake conformance:verify` proves the shared files match
`test/conformance/MANIFEST`. Change the contract only in all three gems at once, as CONTRACT.md describes.
