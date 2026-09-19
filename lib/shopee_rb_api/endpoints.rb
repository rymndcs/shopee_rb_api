# frozen_string_literal: true

module ShopeeRbApi
  # The named hosts, and the only place in this gem that spells out a host. Hosts are configuration, not code:
  # pick one with Client.new(endpoint:), or pass base_url: / auth_base_url: for any other host.
  #
  # api:  the Open API host. Shopee picks it by where the CALLER'S SERVER runs, not by the shop's market
  #       (https://open.shopee.com/developer-guide/16).
  # auth: the host of the seller authorization page (https://open.shopee.com/developer-guide/20).
  ENDPOINTS = {
    sg: { api: "https://partner.shopeemobile.com", auth: "https://open.shopee.com" }.freeze,
    cn: { api: "https://openplatform.shopee.cn", auth: "https://open.shopee.cn" }.freeze,
    br: { api: "https://openplatform.shopee.com.br", auth: "https://open.shopee.com.br" }.freeze,
    sandbox: {
      api: "https://openplatform.sandbox.test-stable.shopee.sg", auth: "https://open.sandbox.test-stable.shopee.com"
    }.freeze,
    sandbox_cn: {
      api: "https://openplatform.sandbox.test-stable.shopee.cn", auth: "https://open.sandbox.test-stable.shopee.cn"
    }.freeze
  }.freeze

  module Endpoints
    # The endpoint used when Client.new gets no endpoint:. Change it here, and only here.
    DEFAULT = :sg

    AUTH_PAGE = "/auth"

    TOKEN_GET = "/api/v2/auth/token/get"
    TOKEN_REFRESH = "/api/v2/auth/access_token/get"
    TOKEN_BY_RESEND_CODE = "/api/v2/public/get_token_by_resend_code"
    SHOPS_BY_PARTNER = "/api/v2/public/get_shops_by_partner"

    SHOP_INFO = "/api/v2/shop/get_shop_info"
    WAREHOUSE_DETAIL = "/api/v2/shop/get_warehouse_detail"
    CHANNEL_LIST = "/api/v2/logistics/get_channel_list"
    UPLOAD_IMAGE = "/api/v2/media_space/upload_image"

    ITEM_LIMIT = "/api/v2/product/get_item_limit"
    CATEGORY = "/api/v2/product/get_category"
    ATTRIBUTE_TREE = "/api/v2/product/get_attribute_tree"
    CATEGORY_RECOMMEND = "/api/v2/product/category_recommend"
    # Documented as v2.product.get_variations, served (and signed) at this path.
    VARIATION_TREE = "/api/v2/product/get_variation_tree"
    BRAND_LIST = "/api/v2/product/get_brand_list"
    SEARCH_ATTRIBUTE_VALUE_LIST = "/api/v2/product/search_attribute_value_list"
    CERTIFICATION_RULE = "/api/v2/product/get_product_certification_rule"

    ADD_ITEM = "/api/v2/product/add_item"
    ITEM_BASE_INFO = "/api/v2/product/get_item_base_info"
    UPDATE_ITEM = "/api/v2/product/update_item"
    ITEM_LIST = "/api/v2/product/get_item_list"
    SEARCH_ITEM = "/api/v2/product/search_item"
    UNLIST_ITEM = "/api/v2/product/unlist_item"
    ITEM_VIOLATION_INFO = "/api/v2/product/get_item_violation_info"
    CONTENT_DIAGNOSIS_RESULT = "/api/v2/product/get_item_content_diagnosis_result"

    MODEL_LIST = "/api/v2/product/get_model_list"
    INIT_TIER_VARIATION = "/api/v2/product/init_tier_variation"
    UPDATE_TIER_VARIATION = "/api/v2/product/update_tier_variation"
    UPDATE_STOCK = "/api/v2/product/update_stock"
    UPDATE_PRICE = "/api/v2/product/update_price"

    ORDER_LIST = "/api/v2/order/get_order_list"
    ORDER_DETAIL = "/api/v2/order/get_order_detail"
  end
  private_constant :Endpoints
end
