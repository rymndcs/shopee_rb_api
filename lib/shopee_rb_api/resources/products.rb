# frozen_string_literal: true

module ShopeeRbApi
  class Products < Resources::Base
    UNLIST_BATCH_MAX = 50
    RELIST_BATCH_MAX = 50
    PAGE_SIZE_MAX = 100
    SEARCH_PAGE_SIZE = 100
    VIOLATIONS_BATCH_MAX = 50
    DIAGNOSES_BATCH_MAX = 48
    private_constant :PAGE_SIZE_MAX, :SEARCH_PAGE_SIZE, :VIOLATIONS_BATCH_MAX, :DIAGNOSES_BATCH_MAX

    # POST /api/v2/product/add_item. The payload is native (item_name, original_price, image, logistic_info, ...).
    # Shopee creates the item WITHOUT variants: add them with shop.variants.init after at least 5 seconds.
    # Not idempotent: a timed-out create may have landed; search by SKU before retrying.
    # https://open.shopee.com/documents/v2/v2.product.add_item?module=89&type=1
    def create(payload, **params)
      session.post(Endpoints::ADD_ITEM, stringify(payload).merge(stringify(params)))
    end

    # GET /api/v2/product/get_item_base_info with item_id_list = [product_id]. Carries item_status and deboost.
    # https://open.shopee.com/documents/v2/v2.product.get_item_base_info?module=89&type=1
    def get(product_id, **params)
      session.get(Endpoints::ITEM_BASE_INFO, { item_id_list: id!(product_id, "product_id") }.merge(params))
    end

    # POST /api/v2/product/update_item: a partial update; only the fields sent change.
    # https://open.shopee.com/documents/v2/v2.product.update_item?module=89&type=1
    def update(product_id, payload, **params)
      body = stringify(payload).merge(stringify(params)).merge("item_id" => id!(product_id, "product_id"))
      session.post(Endpoints::UPDATE_ITEM, body)
    end

    # GET /api/v2/product/get_item_list, offset-paged. Shopee requires item_status (an Array, e.g. ["NORMAL"]),
    # sent as repeated query keys.
    # https://open.shopee.com/documents/v2/v2.product.get_item_list?module=89&type=1
    def list(page_size: nil, cursor: nil, **params)
      size = page_size!(page_size, PAGE_SIZE_MAX)
      Pager.new(cursor:) do |offset|
        response = session.get(Endpoints::ITEM_LIST, params.merge(page_size: size, offset: Integer(offset || 0)))
        page(response, "item", offset_cursor(response.data), response.data["total_count"])
      end
    end

    # GET /api/v2/product/search_item with item_sku. Matches the ITEM-level SKU only, not model SKUs.
    # One request of up to 100 ids. => Array<String>
    # https://open.shopee.com/documents/v2/v2.product.search_item?module=89&type=1
    def find_by_seller_sku(seller_sku)
      raise ArgumentError, "seller_sku is empty" if seller_sku.to_s.empty?

      response = session.get(Endpoints::SEARCH_ITEM, { item_sku: seller_sku.to_s, page_size: SEARCH_PAGE_SIZE })
      Array(response.data["item_id_list"]).map(&:to_s)
    end

    # POST /api/v2/product/unlist_item with unlist: true. Per-item failures are in #item_errors.
    # https://open.shopee.com/documents/v2/v2.product.unlist_item?module=89&type=1
    def unlist(product_ids)
      set_listed(product_ids, unlist: true, max: UNLIST_BATCH_MAX)
    end

    # POST /api/v2/product/unlist_item with unlist: false. Per-item failures are in #item_errors.
    # https://open.shopee.com/documents/v2/v2.product.unlist_item?module=89&type=1
    def relist(product_ids)
      set_listed(product_ids, unlist: false, max: RELIST_BATCH_MAX)
    end

    # Extension. GET /api/v2/product/get_item_violation_info (up to 50 ids). Per-item fail_error in #item_errors.
    # https://open.shopee.com/documents/v2/v2.product.get_item_violation_info?module=89&type=1
    def violations(product_ids)
      ids = ids!(product_ids, "product_ids", VIOLATIONS_BATCH_MAX)
      session.get(Endpoints::ITEM_VIOLATION_INFO, { item_id_list: ids.join(",") })
    end

    # Extension. POST /api/v2/product/get_item_content_diagnosis_result (up to 48 ids).
    # https://open.shopee.com/documents/v2/v2.product.get_item_content_diagnosis_result?module=89&type=1
    def diagnoses(product_ids)
      ids = ids!(product_ids, "product_ids", DIAGNOSES_BATCH_MAX)
      session.post(Endpoints::CONTENT_DIAGNOSIS_RESULT, { "item_id_list" => ids }, idempotent: true)
    end

    private

    def set_listed(product_ids, unlist:, max:)
      ids = ids!(product_ids, "product_ids", max)
      body = { "item_list" => ids.map { |id| { "item_id" => id, "unlist" => unlist } } }
      session.post(Endpoints::UNLIST_ITEM, body, idempotent: true)
    end
  end
end
