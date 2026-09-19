# frozen_string_literal: true

require "openssl"
require "stringio"

# The Shopee half of the conformance suite: everything platform-specific the shared tests in test/conformance/ need.
# See test/conformance/helper.rb for the interface.
module ConformanceAdapter
  # Signing vectors: the partner_id, path, timestamp, token and ids of the worked examples in
  # https://open.shopee.com/developer-guide/16, and the partner key string from Shopee's own PHP demo there.
  PARTNER_ID = 2_001_887
  PARTNER_KEY = "57615053704d6470644f554a78656d50484143644964436a5568777544524579"
  ACCESS_TOKEN = "59777174636562737266615546704c6d"
  SHOP_ID = 14_701_711
  FIXED_TIME = Time.at(1_655_714_431).utc
  REFRESH_TOKEN = "4c7259534969484e71734d695a6e6d55"
  AUTH_CODE = "5a5477794a55537954697169514f4653"
  PUSH_URL = "https://example.com/shopee/push"

  module_function

  def gem_module
    ShopeeRbApi
  end

  def gem_name
    "shopee_rb_api"
  end

  def fixed_time
    FIXED_TIME
  end

  def build_client(transport:, clock: nil, logger: nil, retry_policy: nil, **)
    ShopeeRbApi::Client.new(app_key: PARTNER_ID, app_secret: PARTNER_KEY, transport:, clock: clock || -> { FIXED_TIME },
                            logger:, retry_policy: retry_policy || ShopeeRbApi::RetryPolicy.none, **)
  end

  def locator
    { shop_id: SHOP_ID }
  end

  def build_shop(client)
    client.shop(access_token: ACCESS_TOKEN, **locator)
  end

  def secrets
    tokens = %w[public_get_access_token public_refresh_access_token].flat_map do |name|
      Fixtures.body(name).values_at("access_token", "refresh_token")
    end
    [PARTNER_KEY, ACCESS_TOKEN, REFRESH_TOKEN, AUTH_CODE, *tokens]
  end

  def authorize(client)
    client.auth.authorize_url(redirect_uri: "https://wms.example/online/shopee/callback", state: "csrf-token")
  end

  def read_call
    ->(_client, shop) { shop.info }
  end

  def read_success_response
    Fixtures.response("shop_get_shop_info")
  end

  def error(code, message, request_id: "e3e3e7f3314a5c09fbf56b4649990b01", status: 200)
    FakeTransport.json({ "error" => code, "message" => message, "request_id" => request_id }, status:)
  end

  def server_error_response
    error("error_server", "Something wrong. Please try later.")
  end

  def rate_limit_response
    error("error_rate_limit", "Too many requests. You have reached the rate limit. Please try again later.")
  end

  def unmapped_error_response
    error("error_not_documented_anywhere", "A code the error table has never seen.")
  end

  def error_samples
    [
      ["AuthenticationError", "error_auth", "Invalid access_token.", false],
      ["AppCredentialsError", "error_auth", "partner_id is invalid", false],
      ["PermissionError", "error_api_permission", "This app type has no permission to this API.", false],
      ["SignatureError", "error_sign", "Wrong sign.", false],
      ["SignatureError", "error_param", "Timestamp is expired.", false],
      ["RequestError", "error_param", "There is no shop_id in query.", false],
      ["RateLimitError", "error_rate_limit", "Too many requests. You have reached the rate limit.", true],
      ["QuotaExceededError", "error_limit", "The total API call number made by your APP has reached the daily API " \
                                            "call limit, please try again after 00:00 (UTC+08:00)", true, :positive],
      ["ServerError", "error_server", "Something wrong. Please try later.", true],
      ["BusinessError", "error_auth", "Please wait for the holiday mode set then to edit item. Please try later.",
       false],
      ["BusinessError", "error_item_not_found", "Item_id is not found.", false]
    ].map do |class_name, code, message, retryable, retry_after|
      { class_name:, response: error(code, message), code:, request_id: "e3e3e7f3314a5c09fbf56b4649990b01",
        retryable:, retry_after: }
    end
  end

  def error_classes_without_platform_code
    %w[ConcurrencyError]
  end

  def shared_calls
    t = FIXED_TIME.to_i
    {
      "auth.exchange_code" => [->(c, _) { c.auth.exchange_code(code: AUTH_CODE, shop_id: SHOP_ID) },
                               "public_get_access_token"],
      "auth.refresh" => [->(c, _) { c.auth.refresh(refresh_token: REFRESH_TOKEN, shop_id: SHOP_ID) },
                         "public_refresh_access_token"],
      "client.authorized_shops" => [->(c, _) { c.authorized_shops }, "public_get_shops_by_partner"],
      "client.request" => [->(c, _) { c.request(:get, "/api/v2/public/get_shops_by_partner", query: { page_no: 1 }) },
                           "public_get_shops_by_partner"],
      "shop.info" => [->(_, s) { s.info }, "shop_get_shop_info"],
      "shop.limits" => [->(_, s) { s.limits(category_id: 102_301) }, "product_get_item_limit"],
      "shop.request" => [->(_, s) { s.request(:get, "/api/v2/product/get_category", query: { language: "en" }) },
                         "product_get_category"],
      "categories.list" => [->(_, s) { s.categories.list(language: "en") }, "product_get_category"],
      "categories.attributes" => [->(_, s) { s.categories.attributes(102_301) }, "product_get_attribute_tree"],
      "categories.recommend" => [->(_, s) { s.categories.recommend(title: "Bosch H4 bulb") },
                                 "product_category_recommend"],
      "brands.list" => [->(_, s) { s.brands.list(category_id: 102_301, status: 1) }, "product_get_brand_list"],
      "media.upload_image" => [->(_, s) { s.media.upload_image(StringIO.new("\xFF\xD8\xFFjpeg".b), filename: "a.jpg") },
                               "media_space_upload_image"],
      "products.create" => [->(_, s) { s.products.create(item_payload) }, "product_add_item"],
      "products.get" => [->(_, s) { s.products.get(34_002) }, "product_get_item_base_info"],
      "products.update" => [->(_, s) { s.products.update(34_002, { item_name: "Bosch H4 bulb 12V" }) },
                            "product_update_item"],
      "products.list" => [->(_, s) { s.products.list(item_status: ["NORMAL"]) }, "product_get_item_list"],
      "products.find_by_seller_sku" => [->(_, s) { s.products.find_by_seller_sku("OT405") }, "product_search_item"],
      "products.unlist" => [->(_, s) { s.products.unlist([2_300_069_665, 2_400_143_710]) }, "product_unlist_item"],
      "products.relist" => [->(_, s) { s.products.relist([2_400_143_710]) }, "product_unlist_item"],
      "stock.get" => [->(_, s) { s.stock.get(178_312) }, "product_get_model_list"],
      "stock.update" => [->(_, s) { s.stock.update(1000, [{ model_id: 0, seller_stock: [{ stock: 5 }] }]) },
                         "product_update_stock"],
      "prices.update" => [->(_, s) { s.prices.update(1000, [{ model_id: 0, original_price: 638 }]) },
                          "product_update_price"],
      "orders.list" => [->(_, s) { s.orders.list(time_range_field: "update_time", time_from: t - 86_400, time_to: t) },
                        "order_get_order_list"],
      "orders.get" => [->(_, s) { s.orders.get("201218V2Y6E59M") }, "order_get_order_detail"]
    }.map { |name, (call, fixture)| { name:, call:, response: Fixtures.response(fixture) } }
  end

  def item_payload
    { item_name: "Bosch H4 bulb", description: "Halogen headlight bulb, 12V 60/55W.", original_price: 638,
      weight: 0.2, category_id: 102_301, image: { image_id_list: ["sg-11134201-7r98o"] },
      logistic_info: [{ logistic_id: 80_101, enabled: true }] }
  end

  def write_calls
    names = Conformance::CONTRACT[:write_idempotency].keys
    shared_calls.select { |c| names.include?(c[:name]) }.map do |c|
      c.merge(call: lambda { |shop|
        c[:call].call(nil, shop)
      })
    end
  end

  def batch_calls
    [
      { name: "products.unlist", call: ->(shop, ids) { shop.products.unlist(ids) } },
      { name: "products.relist", call: ->(shop, ids) { shop.products.relist(ids) } }
    ]
  end

  def envelope_samples
    unlist = Fixtures.body("product_unlist_item")
    info = Fixtures.body("shop_get_shop_info")
    variations = Fixtures.body("product_get_variations")
    limit = Fixtures.body("product_get_item_limit")
    warehouses = Fixtures.body("shop_get_warehouse_detail")
    [
      { name: "payload under response, with per-item failures", call: ->(_, s) { s.products.unlist([2_300_069_665]) },
        response: Fixtures.response("product_unlist_item"),
        expect: { data: unlist["response"], request_id: unlist["request_id"], warnings: [],
                  item_errors: [["2300069665", "", "Can't unlist item when item is under promotion"]] } },
      { name: "payload at top level", call: ->(_, s) { s.info }, response: Fixtures.response("shop_get_shop_info"),
        expect: { data: info.except("error", "message", "request_id"), request_id: info["request_id"], warnings: [],
                  item_errors: [] } },
      { name: "payload under data, with a warning", call: ->(_, s) { s.categories.variations(100_001) },
        response: Fixtures.response("product_get_variations"),
        expect: { data: variations["data"], request_id: "xxx", warnings: ["success"], item_errors: [] } },
      { name: "a sibling of response is kept", call: ->(_, s) { s.limits },
        response: Fixtures.response("product_get_item_limit"),
        expect: { data: limit["response"].merge("gtin_limit" => limit["gtin_limit"]),
                  request_id: limit["request_id"], warnings: [], item_errors: [] } },
      { name: "response is an Array", call: lambda { |_, s|
        s.warehouses
      }, response: Fixtures.response("shop_get_warehouse_detail"),
        expect: { data: warehouses["response"], request_id: warehouses["request_id"], warnings: [], item_errors: [] } }
    ]
  end

  def uncoerced_sample
    { call: ->(_, s) { s.request(:get, "/api/v2/product/search_item", query: { item_sku: "OT405", page_size: 10 }) },
      response: Fixtures.response("product_search_item"), checks: [[%w[item_id_list], [653_211, 564_331]],
                                                                   [%w[next_offset], "xsszxjcdeahx"]] }
  end

  # Builds one page of a Shopee list response from a fixture.
  def page_of(fixture, items_key, items, **fields)
    body = Fixtures.body(fixture)
    inner = body.key?("response") ? body["response"].merge(items_key => items) : body.merge(items_key => items)
    fields.each { |k, v| v == :absent ? inner.delete(k.to_s) : inner[k.to_s] = v }
    FakeTransport.json(body.key?("response") ? body.merge("response" => inner) : inner)
  end

  def pagers
    [offset_pager("products.list", "product_get_item_list", "item", lambda { |_, s, **o|
      s.products.list(item_status: ["NORMAL"], **o)
    }),
     offset_pager("brands.list", "product_get_brand_list", "brand_list",
                  ->(_, s, **o) { s.brands.list(category_id: 102_301, status: 1, **o) }),
     orders_pager, attributes_pager, authorized_shops_pager]
  end

  def offset_pager(name, fixture, key, call)
    item = ->(n) { { "item_id" => n, "brand_id" => n } }
    { name:, call:, page_size_key: :page_size, max_page_size: 100, cap: nil,
      pages: [page_of(fixture, key, [item[1], item[2]], has_next_page: true, next_offset: 2),
              page_of(fixture, key, [item[3], item[4]], has_next_page: true, next_offset: 4),
              page_of(fixture, key, [item[5]], has_next_page: false, next_offset: 5)],
      final_variants: [page_of(fixture, key, [item[3]], has_next_page: false, next_offset: 3),
                       page_of(fixture, key, [item[3]], has_next_page: :absent, next_offset: :absent)] }
  end

  def orders_pager
    t = FIXED_TIME.to_i
    order = ->(sn) { { "order_sn" => sn } }
    f = "order_get_order_list"
    { name: "orders.list", page_size_key: :page_size, max_page_size: 100, cap: nil,
      call: ->(_, s, **o) { s.orders.list(time_range_field: "create_time", time_from: t - 86_400, time_to: t, **o) },
      pages: [page_of(f, "order_list", [order["A1"], order["A2"]], more: true, next_cursor: "20"),
              page_of(f, "order_list", [order["A3"]], more: true, next_cursor: "40"),
              page_of(f, "order_list", [order["A4"]], more: false, next_cursor: "")],
      final_variants: [page_of(f, "order_list", [order["A3"]], more: true, next_cursor: ""),
                       page_of(f, "order_list", [order["A3"]], more: :absent, next_cursor: :absent)] }
  end

  def attributes_pager
    f = "product_search_attribute_value_list"
    value = ->(n) { { "value_id" => n, "value_name" => "V#{n}" } }
    info = ->(cursor, more) { { "cursor" => cursor, "has_next" => more } }
    { name: "attributes.search_values", page_size_key: :limit, max_page_size: 100, cap: nil,
      call: ->(_, s, **o) { s.attributes.search_values(attribute_id: 101_777, value_name: "H4", **o) },
      pages: [page_of(f, "value_list", [value[1]], page_info: info[1, true]),
              page_of(f, "value_list", [value[2]], page_info: info[2, true]),
              page_of(f, "value_list", [value[3]], page_info: info[3, false])],
      final_variants: [page_of(f, "value_list", [value[2]], page_info: info[2, false]),
                       page_of(f, "value_list", [value[2]], page_info: :absent)] }
  end

  def authorized_shops_pager
    f = "public_get_shops_by_partner"
    shop = ->(n) { { "shop_id" => n, "region" => "PH", "auth_time" => 1_610_533_441, "expire_time" => 1_642_069_441 } }
    { name: "client.authorized_shops", page_size_key: nil, max_page_size: nil, cap: nil, resumable: false,
      call: ->(c, _, **o) { c.authorized_shops(**o) },
      pages: [page_of(f, "authed_shop_list", [shop[1]], more: true),
              page_of(f, "authed_shop_list", [shop[2]], more: true),
              page_of(f, "authed_shop_list", [shop[3]], more: false)],
      final_variants: [page_of(f, "authed_shop_list", [shop[2]], more: false),
                       page_of(f, "authed_shop_list", [shop[2]], more: :absent)] }
  end

  # The same request, whatever its timestamp and signature.
  def request_identity(request)
    [request.http_method, request.path, request.query.except("sign", "timestamp"), request.body]
  end

  def signer
    ShopeeRbApi.const_get(:Signer)
  end

  def signing_vectors
    base = { partner_id: PARTNER_ID, timestamp: FIXED_TIME.to_i }
    [
      { name: "Shop API", expected_signature: "b914bea03c13799deb036bb9d10e689f5a6bade160c44af568646f1ef7d796c1",
        expected_base_string: "2001887/api/v2/shop/get_shop_info165571443159777174636562737266615546704c6d14701711",
        parts: base.merge(path: "/api/v2/shop/get_shop_info", access_token: ACCESS_TOKEN, shop_id: SHOP_ID) },
      { name: "Merchant API", expected_signature: "a50a2229b148e76048e21ad69a9d619885a21bd4aa7738bc524e1207df73a151",
        expected_base_string: "2001887/api/v2/global_product/get_category1655714431" \
                              "09777174636962737266615546704c6d1000000",
        parts: base.merge(path: "/api/v2/global_product/get_category", access_token: "09777174636962737266615546704c6d",
                          merchant_id: 1_000_000) },
      { name: "Public API", expected_signature: "60ab8c4a535009ab33b8a0029ee18a667ef6eaeb16481ed3d573a5059122d4df",
        expected_base_string: "2001887/api/v2/public/get_shops_by_partner1655714431",
        parts: base.merge(path: "/api/v2/public/get_shops_by_partner") }
    ].map do |v|
      string = signer.base_string(**v[:parts])
      v.merge(base_string: string, signature: signer.sign(PARTNER_KEY, string))
    end
  end

  def signed_calls
    names = %w[shop.info client.authorized_shops products.create media.upload_image auth.exchange_code orders.list]
    shared_calls.select { |c| names.include?(c[:name]) }.map do |c|
      c.merge(token: c[:name].start_with?("shop.", "products.", "orders.") ? ACCESS_TOKEN : nil)
    end
  end

  def signature_parts(request)
    query = request.query
    { signature: query["sign"], timestamp: Integer(query["timestamp"]), access_token: query["access_token"] }
  end

  # Recomputed from the request as sent, following guide 16 directly rather than the gem's Signer.
  def expected_signature(request)
    q = request.query
    raise "partner_id missing from the query" unless q["partner_id"] == PARTNER_ID.to_s

    OpenSSL::HMAC.hexdigest("SHA256", PARTNER_KEY, "#{q["partner_id"]}#{request.path}#{q["timestamp"]}" \
                                                   "#{q["access_token"]}#{q["shop_id"]}")
  end

  def timestamp_for(time)
    time.to_i
  end

  # Shopee does not sign the body.
  def signed_body(_request)
    nil
  end

  def webhook_credentials
    { app_key: PARTNER_ID.to_s, app_secret: PARTNER_KEY }
  end

  def webhook_url_required?
    true
  end

  def webhook_vectors
    guide_body = '{"shop_id": 123, "code": 1, "success": 1, "extra": "shop_id 123 is authorized successfully", ' \
                 '"data": {"more_info": "more info"}, "timestamp": 1470198856}'
    [
      { name: "shopee plan §9 push vector", url: PUSH_URL, raw_body: '{"shop_id":123,"code":1}',
        signature: "5f2ca9f6c64e58aa5af5d28ae9e62a49363df59072cdc501232e444720923f89" },
      { name: "guide 18 example body (HMAC derived with Python hmac)", url: PUSH_URL, raw_body: guide_body,
        signature: "5d72f98932c644f0911b33571b2e0a37e2b3217600a41c08ba02a847b46e715e" }
    ]
  end

  def webhook_parse_samples
    [
      { raw_body: webhook_vectors.last[:raw_body],
        expect: { type: :other, code: "1", shop_id: "123", occurred_at: Time.at(1_470_198_856).utc } },
      { raw_body: '{"code":12,"timestamp":1760000000,"data":{"shop_id_list":[14701711,14701712]}}',
        expect: { type: :authorization_expiring, code: "12", shop_id: nil, occurred_at: Time.at(1_760_000_000).utc } },
      { raw_body: '{"shop_id":14701711,"code":2,"timestamp":1760000100,"data":{}}',
        expect: { type: :deauthorized, code: "2", shop_id: "14701711", occurred_at: Time.at(1_760_000_100).utc } }
    ]
  end

  def token_samples
    exchange = Fixtures.body("public_get_access_token")
    refresh = Fixtures.body("public_refresh_access_token")
    [
      { name: "exchange_code", call: ->(c) { c.auth.exchange_code(code: AUTH_CODE, shop_id: SHOP_ID) },
        response: Fixtures.response("public_get_access_token"),
        expect: { access_token: exchange["access_token"], refresh_token: exchange["refresh_token"],
                  access_expires_in: exchange["expire_in"], refresh_expires_in: nil,
                  shop_ids: %w[368765100 368765098 368765097] } },
      { name: "refresh", call: ->(c) { c.auth.refresh(refresh_token: REFRESH_TOKEN, shop_id: 322_300_222) },
        response: Fixtures.response("public_refresh_access_token"),
        expect: { access_token: refresh["access_token"], refresh_token: refresh["refresh_token"],
                  access_expires_in: 14_400, refresh_expires_in: nil, shop_ids: %w[322300222] } }
    ]
  end

  def extension_files
    %w[lib/shopee_rb_api/resources/variants.rb lib/shopee_rb_api/resources/attributes.rb]
  end
end
