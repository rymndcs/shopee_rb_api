# frozen_string_literal: true

# Wire-shape tests check several fields of one request, so they assert many times.
# rubocop:disable Minitest/MultipleAssertions

require_relative "unit_helper"

class AuthTest < Minitest::Test
  include UnitHelper

  def test_authorize_url_follows_the_authorization_guide
    client, = client_with
    url = client.auth.authorize_url(redirect_uri: "https://wms.example/cb?x=1", state: "s 1")

    assert_equal "https://open.shopee.com/auth?partner_id=2001887&auth_type=seller&" \
                 "redirect_uri=https%3A%2F%2Fwms.example%2Fcb%3Fx%3D1&response_type=code&state=s+1", url
    assert_raises(ArgumentError) { client.auth.authorize_url }
    refute_includes client.auth.authorize_url(redirect_uri: "https://x.test"), "state="
  end

  def test_exchange_code_body
    client, transport = client_with(Fixtures.response("public_get_access_token"))
    grant = client.auth.exchange_code(code: "abc", main_account_id: "99")
    request = transport.requests.first

    assert_equal "/api/v2/auth/token/get", request.path
    assert_equal({ "code" => "abc", "partner_id" => 2_001_887, "main_account_id" => 99 }, request.json)
    assert_nil request.query["access_token"]
    assert_equal %w[368765100 368765098 368765097], grant.shop_ids
    assert_empty grant.merchant_ids
  end

  def test_exchange_code_needs_exactly_one_locator
    client, transport = client_with

    assert_raises(ArgumentError) { client.auth.exchange_code(code: "abc") }
    assert_raises(ArgumentError) { client.auth.exchange_code(code: "abc", shop_id: 1, main_account_id: 2) }
    assert_raises(ArgumentError) { client.auth.exchange_code(code: "abc", merchant_id: 1) }
    assert_raises(ArgumentError) { client.auth.exchange_code(code: "", shop_id: 1) }
    assert_empty transport.requests
  end

  def test_refresh_with_merchant_id
    body = Fixtures.body("public_refresh_access_token").except("shop_id").merge("merchant_id" => 5)
    client, transport = client_with(FakeTransport.json(body))
    grant = client.auth.refresh(refresh_token: "r", merchant_id: 5)

    assert_equal "/api/v2/auth/access_token/get", transport.requests.first.path
    assert_equal({ "refresh_token" => "r", "partner_id" => 2_001_887, "merchant_id" => 5 },
                 transport.requests.first.json)
    assert_equal ["5"], grant.merchant_ids
    assert_empty grant.shop_ids
    assert_raises(ArgumentError) { client.auth.refresh(refresh_token: "r", main_account_id: 1) }
  end

  def test_exchange_resend_code
    client, transport = client_with(Fixtures.response("public_get_token_by_resend_code"))
    grant = client.auth.exchange_resend_code(resend_code: "resend5a4d")

    assert_equal "/api/v2/public/get_token_by_resend_code", transport.requests.first.path
    assert_equal({ "resend_code" => "resend5a4d" }, transport.requests.first.json)
    assert_equal A.fixed_time + 3600, grant.access_token_expires_at
    assert_equal ["123"], grant.shop_ids
    assert_raises(ArgumentError) { client.auth.exchange_resend_code(resend_code: "x", shop_id: 1) }
  end

  def test_token_errors_are_classified
    client, = client_with(A.error("error_shop_refresh_token", "Your refresh token is error ,please check refresh " \
                                                              "token or shopid."))

    assert_raises(ShopeeRbApi::AuthenticationError) { client.auth.refresh(refresh_token: "r", shop_id: 1) }
  end

  def test_authorized_shops_walks_page_numbers
    first = FakeTransport.json(Fixtures.body("public_get_shops_by_partner").merge("more" => true))
    client, transport = client_with(first, Fixtures.response("public_get_shops_by_partner"))
    shops = client.authorized_shops.to_a

    assert_equal(%w[1 2], transport.requests.map { |r| r.query["page_no"] })
    assert_nil transport.requests.first.query["access_token"]
    ref = shops.first

    assert_equal "123", ref.shop_id
    assert_equal "TW", ref.region
    assert_nil ref.name
    assert_equal Time.at(1_642_069_441).utc, ref.authorization_expires_at
    assert_equal({ shop_id: "123" }, ref.locator)
  end

  def test_shop_rejects_a_bad_shop_id_or_empty_token
    client, = client_with

    assert_raises(ArgumentError) { client.shop(access_token: "t", shop_id: "shop-1") }
    assert_raises(ArgumentError) { client.shop(access_token: "", shop_id: 1) }
    assert_equal({ shop_id: "1" }, client.shop(access_token: "t", shop_id: 1).locator)
  end
end
# rubocop:enable Minitest/MultipleAssertions
