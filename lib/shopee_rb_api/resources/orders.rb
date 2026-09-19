# frozen_string_literal: true

module ShopeeRbApi
  class Orders < Resources::Base
    PAGE_SIZE_MAX = 100
    WINDOW_MAX_SECONDS = 15 * 86_400

    # GET /api/v2/order/get_order_list, cursor-paged (more / next_cursor). Shopee requires time_range_field,
    # time_from and time_to (Unix seconds) and caps the window at 15 days; a longer window raises ArgumentError,
    # because the gem never splits windows. Read-only.
    # https://open.shopee.com/documents/v2/v2.order.get_order_list?module=94&type=1
    def list(page_size: nil, cursor: nil, **params)
      check_window!(params)
      size = page_size!(page_size, PAGE_SIZE_MAX)
      Pager.new(cursor:) do |next_cursor|
        response = session.get(Endpoints::ORDER_LIST, params.merge(page_size: size, cursor: next_cursor || ""))
        data = response.data
        more = data["more"] == true && !data["next_cursor"].to_s.empty?
        page(response, "order_list", more ? data["next_cursor"].to_s : nil)
      end
    end

    # GET /api/v2/order/get_order_detail with order_sn_list = order_id. Read-only.
    # Most fields need response_optional_fields in params.
    # https://open.shopee.com/documents/v2/v2.order.get_order_detail?module=94&type=1
    def get(order_id, **params)
      raise ArgumentError, "order_id is empty" if order_id.to_s.empty?

      session.get(Endpoints::ORDER_DETAIL, { order_sn_list: order_id.to_s }.merge(params))
    end

    private

    def check_window!(params)
      from = params[:time_from]
      to = params[:time_to]
      return if from.nil? || to.nil?
      return if to.to_i - from.to_i <= WINDOW_MAX_SECONDS

      raise ArgumentError, "time_from..time_to spans more than 15 days; Shopee rejects it, and the gem never splits " \
                           "windows: step the window yourself"
    end
  end
end
