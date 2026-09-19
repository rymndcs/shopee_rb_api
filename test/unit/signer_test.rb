# frozen_string_literal: true

require_relative "unit_helper"

# Every signing and push vector from the Shopee plan (§3, §9), built on the worked base strings of
# https://open.shopee.com/developer-guide/16 and the push scheme of /developer-guide/18.
class SignerTest < Minitest::Test
  include UnitHelper

  KEY = ConformanceAdapter::PARTNER_KEY

  def signer
    ShopeeRbApi.const_get(:Signer)
  end

  def test_shop_merchant_and_public_vectors
    A.signing_vectors.each do |vector|
      assert_equal vector[:expected_base_string], vector[:base_string], vector[:name]
      assert_equal vector[:expected_signature], vector[:signature], vector[:name]
    end
    assert_equal 3, A.signing_vectors.size
  end

  def test_signature_is_lower_case_hex_keyed_with_the_key_string_not_its_hex_decoding
    signature = signer.sign(KEY, "2001887/api/v2/public/get_shops_by_partner1655714431")

    assert_match(/\A[0-9a-f]{64}\z/, signature)
    refute_equal signature, OpenSSL::HMAC.hexdigest("SHA256", [KEY].pack("H*"), "x")
  end

  def test_push_vectors
    A.webhook_vectors.each do |vector|
      base = signer.push_base_string(vector[:url], vector[:raw_body])

      assert_equal vector[:signature], signer.sign(KEY, base), vector[:name]
      assert ShopeeRbApi::Webhook.verify(raw_body: vector[:raw_body], signature: vector[:signature], app_key: "x",
                                         app_secret: KEY, url: vector[:url])
    end
  end

  def test_push_base_string_handles_binary_bodies
    body = "{\"name\":\"café\"}".b

    assert_equal "https://x.test|#{body}".b, signer.push_base_string("https://x.test", body)
  end

  def test_the_body_and_business_parameters_are_not_signed
    first = request_for { |shop| shop.products.update(1, { item_name: "A" }) }
    second = request_for { |shop| shop.products.update(1, { item_name: "B" }) }

    assert_equal first.query["sign"], second.query["sign"]
  end

  def test_public_calls_carry_no_token_or_shop_id
    request = request_for(Fixtures.response("media_space_upload_image")) do |shop|
      shop.media.upload_image(StringIO.new("img"), filename: "a.png")
    end

    assert_equal %w[partner_id sign timestamp], request.query.keys.sort
  end

  def test_shop_calls_put_the_common_parameters_first_in_the_query
    request = request_for { |shop| shop.products.get(34_002) }

    assert_equal %w[partner_id timestamp access_token shop_id sign item_id_list], request.query_pairs.map(&:first)
  end
end
