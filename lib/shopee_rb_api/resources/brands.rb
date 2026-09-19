# frozen_string_literal: true

module ShopeeRbApi
  class Brands < Resources::Base
    PAGE_SIZE_MAX = 100

    # GET /api/v2/product/get_brand_list, offset-paged (has_next_page / next_offset). Brands are per leaf category,
    # so category_id is required. Shopee also requires `status` (1 normal, 2 pending): pass it in params.
    # https://open.shopee.com/documents/v2/v2.product.get_brand_list?module=89&type=1
    def list(category_id: nil, page_size: nil, cursor: nil, **params)
      raise ArgumentError, "category_id is required: Shopee brands are per leaf category" if category_id.nil?

      query = { category_id: id!(category_id, "category_id"), page_size: page_size!(page_size, PAGE_SIZE_MAX) }
      Pager.new(cursor:) do |offset|
        response = session.get(Endpoints::BRAND_LIST, query.merge(params).merge(offset: Integer(offset || 0)))
        page(response, "brand_list", offset_cursor(response.data))
      end
    end
  end
end
