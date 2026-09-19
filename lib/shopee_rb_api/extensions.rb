# frozen_string_literal: true

module ShopeeRbApi
  # This gem's declared platform extensions (CONTRACT.md "Declared platform extensions"): public surface beyond the
  # shared contract. "Class#member" => what it calls. The conformance suite fails on any public method or constant
  # that is neither in the contract nor declared here.
  EXTENSIONS = {
    "Auth#exchange_resend_code" => "POST /api/v2/public/get_token_by_resend_code",
    "Grant#merchant_ids" => "merchant_id_list / merchant_id of a main-account grant",
    "Shop#variants" => "the Variants resource",
    "Variants#init" => "POST /api/v2/product/init_tier_variation",
    "Variants#update_tiers" => "POST /api/v2/product/update_tier_variation",
    "Variants#list" => "GET /api/v2/product/get_model_list",
    "Categories#variations" => "GET /api/v2/product/get_variation_tree",
    "Shop#attributes" => "the Attributes resource",
    "Attributes#search_values" => "POST /api/v2/product/search_attribute_value_list",
    "Shop#logistics_channels" => "GET /api/v2/logistics/get_channel_list",
    "Shop#warehouses" => "GET /api/v2/shop/get_warehouse_detail",
    "Shop#certification_rules" => "POST /api/v2/product/get_product_certification_rule",
    "Products#violations" => "GET /api/v2/product/get_item_violation_info",
    "Products#diagnoses" => "POST /api/v2/product/get_item_content_diagnosis_result"
  }.freeze
end
