# frozen_string_literal: true

module ShopeeRbApi
  # Extension: Shopee publishes an item and its variants in separate calls.
  class Variants < Resources::Base
    # POST /api/v2/product/init_tier_variation: sets the tier structure and models. Call it at least 5 seconds after
    # add_item (the gem never sleeps). On an item that already has tiers it REPLACES the structure and invalidates
    # every model_id. Not idempotent.
    # https://open.shopee.com/documents/v2/v2.product.init_tier_variation?module=89&type=1
    def init(product_id, payload)
      session.post(Endpoints::INIT_TIER_VARIATION, with_item(product_id, payload))
    end

    # POST /api/v2/product/update_tier_variation: add, remove or re-order options with the structure unchanged.
    # https://open.shopee.com/documents/v2/v2.product.update_tier_variation?module=89&type=1
    def update_tiers(product_id, payload)
      session.post(Endpoints::UPDATE_TIER_VARIATION, with_item(product_id, payload))
    end

    # GET /api/v2/product/get_model_list: tiers and models with model_id, price_info and stock_info_v2.
    # https://open.shopee.com/documents/v2/v2.product.get_model_list?module=89&type=1
    def list(product_id)
      session.get(Endpoints::MODEL_LIST, { item_id: id!(product_id, "product_id") })
    end

    private

    def with_item(product_id, payload)
      stringify(payload).merge("item_id" => id!(product_id, "product_id"))
    end
  end
end
