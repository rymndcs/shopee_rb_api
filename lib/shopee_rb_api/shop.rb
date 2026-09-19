# frozen_string_literal: true

module ShopeeRbApi
  # One shop session: the app client plus this shop's access token and locator. Immutable.
  class Shop
    include Redaction

    LOCATOR_KEYS = %i[shop_id].freeze

    attr_reader :locator, :categories, :brands, :media, :products, :stock, :prices, :orders, :variants, :attributes

    def initialize(connection, access_token:, shop_id:)
      raise ArgumentError, "access_token: is empty" if access_token.to_s.empty?

      id = Resources.integer_id(shop_id, "shop_id")
      @session = Resources::Session.new(connection, access_token: access_token.to_s, shop_id: id)
      @locator = { shop_id: id.to_s }.freeze
      build_resources
      freeze
    end

    # GET /api/v2/shop/get_shop_info. Includes auth_time and expire_time: the seller-chosen authorization deadline.
    # https://open.shopee.com/documents/v2/v2.shop.get_shop_info?module=92&type=1
    def info
      @session.get(Endpoints::SHOP_INFO)
    end

    # GET /api/v2/product/get_item_limit (category_id optional). gtin_limit is documented beside `response`;
    # it is kept in #data.
    # https://open.shopee.com/documents/v2/v2.product.get_item_limit?module=89&type=1
    def limits(**params)
      @session.get(Endpoints::ITEM_LIMIT, params)
    end

    # Extension. GET /api/v2/logistics/get_channel_list: logistic_info is required on add_item.
    # https://open.shopee.com/documents/v2/v2.logistics.get_channel_list?module=95&type=1
    def logistics_channels(**params)
      @session.get(Endpoints::CHANNEL_LIST, params)
    end

    # Extension. GET /api/v2/shop/get_warehouse_detail (warehouse_type optional). #data is an Array.
    # location_id is required on seller_stock entries for multi-warehouse shops.
    # https://open.shopee.com/documents/v2/v2.shop.get_warehouse_detail?module=92&type=1
    def warehouses(**params)
      @session.get(Endpoints::WAREHOUSE_DETAIL, params)
    end

    # Extension. POST /api/v2/product/get_product_certification_rule.
    # https://open.shopee.com/documents/v2/v2.product.get_product_certification_rule?module=89&type=1
    def certification_rules(category_id:, attribute_list:)
      body = { "category_id" => Resources.integer_id(category_id, "category_id"), "attribute_list" => attribute_list }
      @session.post(Endpoints::CERTIFICATION_RULE, body, idempotent: true)
    end

    # The escape hatch: any Shop-type path, signed with this shop's token. One call, one request.
    def request(http_method, path, query: nil, body: nil, idempotent: nil)
      @session.request(http_method, path, query:, body:, idempotent:)
    end

    def inspect
      "#<#{self.class.name} shop_id=#{@locator[:shop_id]} access_token=#{Redaction::REDACTED}>"
    end

    private

    def build_resources
      @categories = Categories.new(@session)
      @brands = Brands.new(@session)
      @media = Media.new(@session)
      @products = Products.new(@session)
      @stock = Stock.new(@session)
      @prices = Prices.new(@session)
      @orders = Orders.new(@session)
      @variants = Variants.new(@session)
      @attributes = Attributes.new(@session)
    end
  end
end
