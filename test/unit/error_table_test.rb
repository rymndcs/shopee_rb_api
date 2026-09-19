# frozen_string_literal: true

# Wire-shape tests check several fields of one request, so they assert many times.
# rubocop:disable Minitest/MultipleAssertions

require_relative "unit_helper"

class ErrorTableTest < Minitest::Test
  include UnitHelper

  def classify(code, message)
    ShopeeRbApi.const_get(:ErrorTable).classify(code, message)
  end

  # test/fixtures/error_list.json holds every (error, message) pair in the error lists of the endpoint docs the gem
  # calls. Re-pull it to detect drift in the docs.
  def test_every_documented_pair_maps_to_exactly_one_documented_class
    pairs = Fixtures.load("error_list")["pairs"]

    assert_operator pairs.size, :>, 250
    unmapped = pairs.select { |pair| classify(pair["error"], pair["message"]) == ShopeeRbApi::ApiError }

    assert_empty(unmapped.map { |pair| pair.values.join(": ") })
    pairs.each do |pair|
      klass = classify(pair["error"], pair["message"])

      assert_operator klass, :<, ShopeeRbApi::ApiError
      assert_equal klass, classify(pair["error"], pair["message"])
    end
  end

  def test_overloaded_error_auth_is_classified_by_message
    {
      "Invalid access_token." => ShopeeRbApi::AuthenticationError,
      "Invalid partner_id or shopid." => ShopeeRbApi::AuthenticationError,
      "partner_id is invalid" => ShopeeRbApi::AppCredentialsError,
      "The App is deleted, and you'll be unable to make any API call." => ShopeeRbApi::AppCredentialsError,
      "No permission to current api." => ShopeeRbApi::PermissionError,
      "System error, please try again later." => ShopeeRbApi::ServerError,
      "Please wait for the holiday mode set then to edit item. Please try later." => ShopeeRbApi::BusinessError,
      "Total stock must be more than reserved stock." => ShopeeRbApi::BusinessError,
      "cnsc shop not upgraded, can not edit item." => ShopeeRbApi::BusinessError
    }.each { |message, klass| assert_equal klass, classify("error_auth", message), message }
  end

  def test_overloaded_error_param_is_classified_by_message
    {
      "There is no sign in query." => ShopeeRbApi::SignatureError,
      "Timestamp is expired." => ShopeeRbApi::SignatureError,
      "Invalid timestamp" => ShopeeRbApi::SignatureError,
      "There is no access_token in query." => ShopeeRbApi::RequestError,
      "Permission denied. This API is currently offline or the request path is incorrect." => ShopeeRbApi::RequestError,
      "Invalid partner_id." => ShopeeRbApi::AppCredentialsError,
      "Wrong parameters, detail: {msg}." => ShopeeRbApi::BusinessError,
      "The level of tier-variation over 2." => ShopeeRbApi::BusinessError
    }.each { |message, klass| assert_equal klass, classify("error_param", message), message }
  end

  def test_families
    assert_equal ShopeeRbApi::SignatureError, classify("error_sign", "Wrong sign.")
    assert_equal ShopeeRbApi::QuotaExceededError, classify("error_limit", "daily limit")
    assert_equal ShopeeRbApi::RateLimitError, classify("error_rate_limit", "Too many requests.")
    assert_equal ShopeeRbApi::AuthenticationError, classify("invalid_acceess_token", "Invalid access_token")
    assert_equal ShopeeRbApi::PermissionError, classify("source_ip_undeclared", "Request Source IP")
    assert_equal ShopeeRbApi::ServerError, classify("error_inner", "Our system is taking some time")
    assert_equal ShopeeRbApi::BusinessError, classify("error_inner", "Invalid stock location ID")
    assert_equal ShopeeRbApi::BusinessError, classify("error_item_not_found", "Item_id is not found.")
    assert_equal ShopeeRbApi::RequestError, classify("api_suspended", "The API is offline.")
    assert_equal ShopeeRbApi::ApiError, classify("error_something_new", "never documented")
  end

  def test_quota_retry_after_runs_to_the_next_midnight_utc8
    now = Time.utc(2026, 9, 19, 15, 30, 0) # 23:30 in UTC+8
    client, = client_with(A.error("error_limit", "daily limit"), clock: -> { now })
    error = assert_raises(ShopeeRbApi::QuotaExceededError) { A.build_shop(client).info }

    assert_in_delta 1800.0, error.retry_after
    assert_predicate error, :retryable?
  end

  def test_retry_after_accepts_an_http_date
    date = (A.fixed_time + 30).httpdate
    client, = client_with(FakeTransport.json("", status: 503, headers: { "retry-after" => date }))
    error = assert_raises(ShopeeRbApi::ServerError) { A.build_shop(client).info }

    assert_in_delta 30.0, error.retry_after
  end

  def test_error_is_raised_whatever_the_http_status
    client, = client_with(A.error("error_auth", "Invalid access_token.", status: 403))
    error = assert_raises(ShopeeRbApi::AuthenticationError) { A.build_shop(client).info }

    assert_equal 403, error.http_status
    assert_equal "/api/v2/shop/get_shop_info", error.endpoint
    assert_equal "Invalid access_token.", error.message
  end

  def test_a_non_empty_error_inside_a_2xx_raises_even_with_a_payload
    body = Fixtures.body("shop_get_warehouse_detail")
                   .merge("error" => "warehouse.error_not_in_whitelist",
                          "message" => "Your shop is not in multi-warehouse whitelist.")
    client, = client_with(FakeTransport.json(body))
    error = assert_raises(ShopeeRbApi::BusinessError) { A.build_shop(client).warehouses }

    assert_kind_of Array, error.response.data
  end
end
# rubocop:enable Minitest/MultipleAssertions
