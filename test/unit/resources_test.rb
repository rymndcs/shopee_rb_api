# frozen_string_literal: true

# Wire-shape tests check several fields of one request, so they assert many times.
# rubocop:disable Minitest/MultipleAssertions

require_relative "unit_helper"

# The method, path, query and body each wrapped endpoint sends, per its official doc page.
class ResourcesTest < Minitest::Test
  include UnitHelper

  def assert_get(request, path, query)
    assert_equal :get, request.http_method
    assert_equal path, request.path
    assert_nil request.body
    query.each { |key, value| assert_equal value, request.query[key], key }
  end

  def assert_post(request, path, body)
    assert_equal :post, request.http_method
    assert_equal path, request.path
    assert_equal "application/json", request.header("Content-Type")
    assert_equal body, request.json
  end

  def test_info_limits_channels_warehouses
    assert_get(request_for(&:info), "/api/v2/shop/get_shop_info", {})
    assert_get(request_for { |s| s.limits(category_id: 5) }, "/api/v2/product/get_item_limit", "category_id" => "5")
    assert_get(request_for(&:logistics_channels), "/api/v2/logistics/get_channel_list", {})
    assert_get(request_for { |s| s.warehouses(warehouse_type: 1) }, "/api/v2/shop/get_warehouse_detail",
               "warehouse_type" => "1")
  end

  def test_certification_rules
    request = request_for { |s| s.certification_rules(category_id: "102301", attribute_list: [{ attribute_id: 1 }]) }

    assert_post(request, "/api/v2/product/get_product_certification_rule",
                "category_id" => 102_301, "attribute_list" => [{ "attribute_id" => 1 }])
  end

  def test_categories
    assert_get(request_for { |s| s.categories.list(language: "en") }, "/api/v2/product/get_category",
               "language" => "en")
    assert_get(request_for { |s| s.categories.attributes("102301", language: "en") },
               "/api/v2/product/get_attribute_tree", "category_id_list" => "102301", "language" => "en")
    assert_get(request_for { |s| s.categories.recommend(title: "Bosch H4", product_cover_image: "img") },
               "/api/v2/product/category_recommend", "item_name" => "Bosch H4", "product_cover_image" => "img")
    assert_get(request_for { |s| s.categories.variations(102_301) }, "/api/v2/product/get_variation_tree",
               "category_id" => "102301")
  end

  def test_products_create_update_get
    assert_post(request_for { |s| s.products.create({ item_name: "A", weight: 0.2 }, item_status: "UNLIST") },
                "/api/v2/product/add_item", "item_name" => "A", "weight" => 0.2, "item_status" => "UNLIST")
    assert_post(request_for { |s| s.products.update("34002", { attribute_list: [] }) },
                "/api/v2/product/update_item", "attribute_list" => [], "item_id" => 34_002)
    assert_get(request_for { |s| s.products.get(34_002, need_tax_info: true) }, "/api/v2/product/get_item_base_info",
               "item_id_list" => "34002", "need_tax_info" => "true")
  end

  def test_products_list_sends_item_status_as_repeated_keys
    response = Fixtures.response("product_get_item_list")
    request = request_for(response) { |s| s.products.list(item_status: %w[NORMAL UNLIST]).first_page }

    assert_get(request, "/api/v2/product/get_item_list", "item_status" => %w[NORMAL UNLIST], "offset" => "0",
                                                         "page_size" => "100")
  end

  def test_products_list_page_carries_total_count
    shop, = shop_with(Fixtures.response("product_get_item_list"))
    page = shop.products.list(item_status: ["NORMAL"], page_size: 10).first_page

    assert_equal 19, page.total
    assert_equal "10", page.next_cursor
    assert_equal([2_500_139_861], page.items.map { |i| i["item_id"] })
  end

  def test_find_by_seller_sku
    shop, transport = shop_with(Fixtures.response("product_search_item"))

    assert_equal %w[653211 564331], shop.products.find_by_seller_sku("OT405")
    assert_get(transport.requests.first, "/api/v2/product/search_item", "item_sku" => "OT405", "page_size" => "100")
    assert_raises(ArgumentError) { shop.products.find_by_seller_sku("") }
  end

  def test_unlist_and_relist
    unlist = request_for { |s| s.products.unlist(%w[1 2]) }
    relist = request_for { |s| s.products.relist([3]) }

    assert_post(unlist, "/api/v2/product/unlist_item",
                "item_list" => [{ "item_id" => 1, "unlist" => true }, { "item_id" => 2, "unlist" => true }])
    assert_post(relist, "/api/v2/product/unlist_item", "item_list" => [{ "item_id" => 3, "unlist" => false }])
    assert_equal 50, ShopeeRbApi::Products::UNLIST_BATCH_MAX
    assert_equal 50, ShopeeRbApi::Products::RELIST_BATCH_MAX
  end

  def test_unlist_failures_are_item_errors
    shop, = shop_with(Fixtures.response("product_unlist_item"))
    response = shop.products.relist([2_300_069_665, 2_400_143_710])

    assert_equal ["2300069665"], response.item_errors.map(&:id)
    assert_equal "Can't unlist item when item is under promotion", response.item_errors.first.message
  end

  def test_violations_and_diagnoses
    assert_get(request_for { |s| s.products.violations([1, "2"]) }, "/api/v2/product/get_item_violation_info",
               "item_id_list" => "1,2")
    assert_post(request_for { |s| s.products.diagnoses([1, 2]) }, "/api/v2/product/get_item_content_diagnosis_result",
                "item_id_list" => [1, 2])
    shop, = shop_with
    assert_raises(ArgumentError) { shop.products.violations((1..51).to_a) }
    assert_raises(ArgumentError) { shop.products.diagnoses((1..49).to_a) }
  end

  def test_diagnosis_failures_are_item_errors
    shop, = shop_with(Fixtures.response("product_get_item_content_diagnosis_result"))
    errors = shop.products.diagnoses([843_988_729]).item_errors

    assert_equal ["843988729"], errors.map(&:id)
  end

  def test_stock_and_prices
    assert_get(request_for { |s| s.stock.get(178_312) }, "/api/v2/product/get_model_list", "item_id" => "178312")
    skus = [{ "model_id" => 0, "seller_stock" => [{ "location_id" => "PHZ", "stock" => 3 }] }]

    assert_post(request_for { |s| s.stock.update(1000, skus) }, "/api/v2/product/update_stock",
                "item_id" => 1000, "stock_list" => skus)
    prices = [{ "model_id" => 0, "original_price" => 638 }]

    assert_post(request_for { |s| s.prices.update(1000, prices) }, "/api/v2/product/update_price",
                "item_id" => 1000, "price_list" => prices)
    shop, = shop_with
    assert_raises(ArgumentError) { shop.stock.update(1, Array.new(51) { {} }) }
    assert_raises(ArgumentError) { shop.prices.update(1, []) }
  end

  def test_stock_update_failures_are_item_errors
    shop, = shop_with(Fixtures.response("product_update_price"))
    errors = shop.prices.update(1000, [{ model_id: 3456, original_price: 1 }]).item_errors

    assert_equal([%w[3456 fail]], errors.map { |e| [e.id, e.message] })
  end

  def test_variants
    assert_post(request_for { |s| s.variants.init(7, { model: [] }) }, "/api/v2/product/init_tier_variation",
                "model" => [], "item_id" => 7)
    assert_post(request_for { |s| s.variants.update_tiers(7, { model_list: [] }) },
                "/api/v2/product/update_tier_variation", "model_list" => [], "item_id" => 7)
    assert_get(request_for { |s| s.variants.list(7) }, "/api/v2/product/get_model_list", "item_id" => "7")
  end

  def test_orders
    t = A.fixed_time.to_i
    request = request_for(Fixtures.response("order_get_order_list")) do |s|
      s.orders.list(time_range_field: "create_time", time_from: t - 86_400, time_to: t, order_status: "READY_TO_SHIP")
       .first_page
    end

    assert_get(request, "/api/v2/order/get_order_list", "cursor" => "", "page_size" => "100",
                                                        "order_status" => "READY_TO_SHIP")
    assert_get(request_for { |s| s.orders.get("201218V2Y6E59M", response_optional_fields: "buyer_user_id") },
               "/api/v2/order/get_order_detail", "order_sn_list" => "201218V2Y6E59M")
  end

  def test_orders_window_over_15_days_raises_without_a_request
    shop, transport = shop_with
    t = A.fixed_time.to_i

    assert_raises(ArgumentError) do
      shop.orders.list(time_range_field: "create_time", time_from: t - (15 * 86_400) - 1, time_to: t)
    end
    assert_empty transport.requests
    shop.orders.list(time_range_field: "create_time", time_from: t - (15 * 86_400), time_to: t)
  end

  def test_brands
    request = request_for(Fixtures.response("product_get_brand_list")) do |s|
      s.brands.list(category_id: 102_301, status: 1, page_size: 10).first_page
    end

    assert_get(request, "/api/v2/product/get_brand_list", "category_id" => "102301", "status" => "1",
                                                          "offset" => "0", "page_size" => "10")
    shop, = shop_with
    assert_raises(ArgumentError) { shop.brands.list(status: 1) }
  end

  def test_attribute_value_search
    response = Fixtures.response("product_search_attribute_value_list")
    request = request_for(response) do |s|
      s.attributes.search_values(attribute_id: 101_777, value_name: "H4").first_page
    end

    assert_post(request, "/api/v2/product/search_attribute_value_list",
                "value_name" => "H4", "attribute_id" => 101_777, "limit" => 100, "cursor" => 0)
  end

  def test_upload_image_is_multipart_and_public_signed
    shop, transport = shop_with(Fixtures.response("media_space_upload_image"))
    shop.media.upload_image(StringIO.new("\x89PNGdata".b), filename: "bulb.png", scene: "normal")
    request = transport.requests.first
    boundary = request.header("Content-Type")[/boundary=(.+)\z/, 1]

    assert_equal "/api/v2/media_space/upload_image", request.path
    assert_nil request.query["access_token"]
    assert_includes request.body, "--#{boundary}\r\nContent-Disposition: form-data; name=\"scene\"\r\n\r\nnormal\r\n"
    assert_includes request.body,
                    "name=\"image\"; filename=\"bulb.png\"\r\nContent-Type: image/png\r\n\r\n\x89PNGdata".b
    assert request.body.end_with?("--#{boundary}--\r\n")
  end

  def test_upload_image_names_a_file_after_its_path
    request = File.open(File.join(Fixtures::DIR, "product_get_category.json")) do |file|
      request_for(Fixtures.response("media_space_upload_image")) { |s| s.media.upload_image(file) }
    end

    assert_includes request.body, "filename=\"product_get_category.json\""
    assert_includes request.body, "Content-Type: application/octet-stream"
  end

  def test_identity_arguments_must_be_integers
    shop, transport = shop_with

    assert_raises(ArgumentError) { shop.products.get("abc") }
    assert_raises(ArgumentError) { shop.categories.attributes(nil) }
    assert_empty transport.requests
  end

  def test_shop_escape_hatch
    request = request_for { |s| s.request(:post, "/api/v2/product/delete_item", body: { item_id: 1 }) }

    assert_post(request, "/api/v2/product/delete_item", "item_id" => 1)
    assert_equal ConformanceAdapter::ACCESS_TOKEN, request.query["access_token"]
  end
end
# rubocop:enable Minitest/MultipleAssertions
