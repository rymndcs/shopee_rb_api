# frozen_string_literal: true

module ShopeeRbApi
  # Extension: searching the values of large attribute enums (attribute_info.support_search_value).
  class Attributes < Resources::Base
    LIMIT_MAX = 100

    # POST /api/v2/product/search_attribute_value_list, int-cursor paged (page_info.cursor / has_next).
    # Native params: value_name, limit (page size, 1..100, default 100) and cursor (default 0).
    # https://open.shopee.com/documents/v2/v2.product.search_attribute_value_list?module=89&type=1
    def search_values(attribute_id:, **params)
      params = params.dup
      limit = page_size!(params.delete(:limit), LIMIT_MAX)
      start = params.delete(:cursor)
      body = stringify(params).merge("attribute_id" => id!(attribute_id, "attribute_id"), "limit" => limit)
      Pager.new(cursor: start&.to_s) do |cursor|
        response = session.post(Endpoints::SEARCH_ATTRIBUTE_VALUE_LIST, body.merge("cursor" => Integer(cursor || 0)),
                                idempotent: true)
        info = response.data["page_info"] || {}
        page(response, "value_list", info["has_next"] == true && !info["cursor"].nil? ? info["cursor"].to_s : nil)
      end
    end
  end
end
