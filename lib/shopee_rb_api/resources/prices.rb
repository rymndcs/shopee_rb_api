# frozen_string_literal: true

module ShopeeRbApi
  class Prices < Resources::Base
    SKUS_MAX = 50

    # POST /api/v2/product/update_price. skus: native price_list entries, e.g. [{ model_id: 0, original_price: 638 }].
    # Prices are in major units of the shop's currency; PH shops accept integers only.
    # Sets absolute prices, so it is idempotent. Per-model failures are in #item_errors.
    # https://open.shopee.com/documents/v2/v2.product.update_price?module=89&type=1
    def update(product_id, skus)
      body = { "item_id" => id!(product_id, "product_id"), "price_list" => batch!(skus, "skus", SKUS_MAX) }
      session.post(Endpoints::UPDATE_PRICE, body, idempotent: true)
    end
  end
end
