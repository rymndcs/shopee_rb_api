# frozen_string_literal: true

# Wire-shape tests check several fields of one request, so they assert many times.
# rubocop:disable Minitest/MultipleAssertions

require_relative "unit_helper"

class EndpointsTest < Minitest::Test
  include UnitHelper

  # https://open.shopee.com/developer-guide/16 (API hosts) and /20 (authorization page hosts), pulled 2026-09-19.
  DOCUMENTED = {
    sg: %w[https://partner.shopeemobile.com https://open.shopee.com],
    cn: %w[https://openplatform.shopee.cn https://open.shopee.cn],
    br: %w[https://openplatform.shopee.com.br https://open.shopee.com.br],
    sandbox: %w[https://openplatform.sandbox.test-stable.shopee.sg https://open.sandbox.test-stable.shopee.com],
    sandbox_cn: %w[https://openplatform.sandbox.test-stable.shopee.cn https://open.sandbox.test-stable.shopee.cn]
  }.freeze

  def test_the_named_hosts_are_the_documented_ones
    assert_equal DOCUMENTED.keys, ShopeeRbApi::ENDPOINTS.keys
    DOCUMENTED.each do |name, (api, auth)|
      assert_equal({ api:, auth: }, ShopeeRbApi::ENDPOINTS[name])
    end
  end

  def test_default_endpoint_is_sg
    client, = client_with

    assert_equal :sg, client.endpoint
  end

  def test_selecting_each_named_host_sends_api_calls_and_consent_links_there
    DOCUMENTED.each do |name, (api, auth)|
      client, transport = client_with(A.read_success_response, endpoint: name)
      A.build_shop(client).info

      assert_equal "#{api}/api/v2/shop/get_shop_info", transport.requests.first.url.split("?").first, name.to_s
      assert client.auth.authorize_url(redirect_uri: "https://x.test/cb").start_with?("#{auth}/auth?"),
             "#{name} consent host"
    end
  end

  def test_a_custom_api_url_and_a_custom_auth_url
    client, transport = client_with(A.read_success_response, endpoint: :sandbox,
                                                             base_url: "https://shopee-proxy.internal:8443/",
                                                             auth_base_url: "https://open.test-stable.shopee.com")
    A.build_shop(client).info

    assert_equal "https://shopee-proxy.internal:8443/api/v2/shop/get_shop_info",
                 transport.requests.first.url.split("?").first
    assert client.auth.authorize_url(redirect_uri: "https://x.test/cb")
                 .start_with?("https://open.test-stable.shopee.com/auth?")
    assert_equal :sandbox, client.endpoint
  end

  def test_base_url_alone_keeps_the_endpoints_auth_host
    client, = client_with(base_url: "https://api.example.test")

    assert client.auth.authorize_url(redirect_uri: "https://x.test/cb").start_with?("https://open.shopee.com/auth?")
  end

  def test_unknown_endpoint
    error = assert_raises(ShopeeRbApi::ConfigurationError) { client_with(endpoint: :sandbox_br) }

    assert_includes error.message, ":sandbox_cn"
  end

  def test_partner_id_must_be_an_integer_and_the_key_a_string
    assert_raises(ShopeeRbApi::ConfigurationError) do
      ShopeeRbApi::Client.new(app_key: "abc", app_secret: "k", transport: FakeTransport.new)
    end
    assert_raises(ShopeeRbApi::ConfigurationError) do
      ShopeeRbApi::Client.new(app_key: 1, app_secret: "", transport: FakeTransport.new)
    end
    assert_raises(ShopeeRbApi::ConfigurationError) do
      ShopeeRbApi::Client.new(app_key: 1, app_secret: "k", transport: Object.new)
    end
    assert_equal "2001887", ShopeeRbApi::Client.new(app_key: "2001887", app_secret: "k").app_key
  end
end
# rubocop:enable Minitest/MultipleAssertions
