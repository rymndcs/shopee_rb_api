# frozen_string_literal: true

require_relative "live_helper"

# Phase-0 checks from the Shopee plan (§9) that need a real app and shop: the derived signature is accepted, and the
# read endpoints answer in the documented shapes. With SHOPEE_RECORD=1 each response replaces its doc fixture.
class LiveReadsTest < Minitest::Test
  include LiveHelper::Gate

  def shop
    @shop ||= LiveHelper.shop
  end

  def test_signed_shop_call_is_accepted
    info = shop.info

    assert_kind_of String, info.request_id
    assert info.data.key?("expire_time"), "get_shop_info carries the authorization deadline"
  end

  def test_authorized_shops_lists_this_shop
    shops = LiveHelper.client.authorized_shops.first_page.items

    assert(shops.any? { |s| s.shop_id == LiveHelper.env("SHOP_ID") })
  end

  def test_catalogue_reads
    assert_kind_of Array, shop.categories.list(language: "en").data["category_list"]
    assert_kind_of Hash, shop.limits.data
    assert_kind_of Array, shop.logistics_channels.data["logistics_channel_list"]
  end

  def test_products_first_page
    page = shop.products.list(item_status: ["NORMAL"], page_size: 10).first_page

    assert_kind_of Array, page.items
    skip "the shop has no NORMAL items to read" if page.items.empty?

    item_id = page.items.first["item_id"]

    assert_kind_of Array, shop.products.get(item_id).data["item_list"]
    assert_kind_of Hash, shop.stock.get(item_id).data
  end

  def test_warehouses_or_a_documented_refusal
    data = shop.warehouses.data

    assert_kind_of Array, data
  rescue ShopeeRbApi::BusinessError => e
    assert_match(/warehouse/, e.code)
  end

  def test_orders_first_page_of_the_last_day
    now = Time.now.to_i
    page = shop.orders.list(time_range_field: "update_time", time_from: now - 86_400, time_to: now).first_page

    assert_kind_of Array, page.items
  end
end
