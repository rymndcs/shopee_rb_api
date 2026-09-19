# frozen_string_literal: true

module ShopeeRbApi
  class Stock < Resources::Base
    SKUS_MAX = 50

    # GET /api/v2/product/get_model_list: model[].stock_info_v2. For an item without models the stock is on
    # products.get (stock_info_v2).
    # https://open.shopee.com/documents/v2/v2.product.get_model_list?module=89&type=1
    def get(product_id, **params)
      session.get(Endpoints::MODEL_LIST, { item_id: id!(product_id, "product_id") }.merge(params))
    end

    # POST /api/v2/product/update_stock. skus: native stock_list entries,
    # e.g. [{ model_id: 0, seller_stock: [{ location_id: "PHZ", stock: 10 }] }] (model_id 0 = an item without models).
    # Sets absolute stock, so it is idempotent. Per-model failures are in #item_errors.
    # https://open.shopee.com/documents/v2/v2.product.update_stock?module=89&type=1
    def update(product_id, skus)
      body = { "item_id" => id!(product_id, "product_id"), "stock_list" => batch!(skus, "skus", SKUS_MAX) }
      session.post(Endpoints::UPDATE_STOCK, body, idempotent: true)
    end
  end
end
