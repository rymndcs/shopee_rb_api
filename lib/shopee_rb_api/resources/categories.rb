# frozen_string_literal: true

module ShopeeRbApi
  class Categories < Resources::Base
    # GET /api/v2/product/get_category: the whole tree as a flat list (not paged).
    # https://open.shopee.com/documents/v2/v2.product.get_category?module=89&type=1
    def list(**params)
      session.get(Endpoints::CATEGORY, params)
    end

    # GET /api/v2/product/get_attribute_tree with category_id_list = [category_id].
    # https://open.shopee.com/documents/v2/v2.product.get_attribute_tree?module=89&type=1
    def attributes(category_id, **params)
      session.get(Endpoints::ATTRIBUTE_TREE, { category_id_list: id!(category_id, "category_id") }.merge(params))
    end

    # GET /api/v2/product/category_recommend; title is sent as item_name.
    # https://open.shopee.com/documents/v2/v2.product.category_recommend?module=89&type=1
    def recommend(title:, **params)
      session.get(Endpoints::CATEGORY_RECOMMEND, { item_name: title.to_s }.merge(params))
    end

    # Extension. GET /api/v2/product/get_variation_tree (documented as v2.product.get_variations): Shopee's
    # standardised variation vocabulary for a leaf category.
    # https://open.shopee.com/documents/v2/v2.product.get_variations?module=89&type=1
    def variations(category_id)
      session.get(Endpoints::VARIATION_TREE, { category_id: id!(category_id, "category_id") })
    end
  end
end
