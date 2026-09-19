# frozen_string_literal: true

require_relative "unit_helper"

class WebhookTest < Minitest::Test
  include UnitHelper

  def test_authorization_expiry_push_is_code_twelve
    event = ShopeeRbApi::Webhook.parse('{"code":12,"timestamp":1760000000,"data":{"shop_id_list":[1,2]}}')

    assert_equal :authorization_expiring, event.type
    assert_nil event.shop_id
    assert_equal({ "shop_id_list" => [1, 2] }, event.data)
  end

  def test_other_codes_keep_their_code
    event = ShopeeRbApi::Webhook.parse('{"shop_id":7,"code":3,"timestamp":1660123127,"data":{"ordersn":"X"}}')

    assert_equal :other, event.type
    assert_equal "3", event.code
    assert_equal "7", event.shop_id
  end

  def test_data_that_is_not_an_object_is_left_in_raw
    event = ShopeeRbApi::Webhook.parse('{"code":3,"data":"{\"a\":1}"}')

    assert_empty event.data
    assert_equal "{\"a\":1}", event.raw["data"]
    assert_nil event.occurred_at
  end

  def test_invalid_bodies
    assert_raises(ArgumentError) { ShopeeRbApi::Webhook.parse("not json") }
    assert_raises(ArgumentError) { ShopeeRbApi::Webhook.parse("[1]") }
  end

  def test_client_verify_webhook_needs_the_url
    client, = client_with
    vector = A.webhook_vectors.first

    assert_raises(ArgumentError) { client.verify_webhook(raw_body: vector[:raw_body], signature: vector[:signature]) }
  end
end
