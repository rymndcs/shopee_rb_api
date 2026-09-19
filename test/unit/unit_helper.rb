# frozen_string_literal: true

require "test_helper"
require "conformance_adapter"

# Shopee unit-test helpers on top of the conformance adapter's fixed credentials and clock.
module UnitHelper
  A = ConformanceAdapter

  def client_with(*responses, **)
    transport = FakeTransport.new(*responses)
    [A.build_client(transport:, **), transport]
  end

  def shop_with(*responses, **)
    client, transport = client_with(*responses, **)
    [A.build_shop(client), transport]
  end

  def ok(body = {})
    FakeTransport.json({ "error" => "", "message" => "", "request_id" => "r1", "response" => body })
  end

  # Runs the block against a shop answering `response` and returns the one request it made.
  def request_for(response = ok, &)
    shop, transport = shop_with(response)
    yield(shop)

    assert_equal 1, transport.requests.size
    transport.requests.first
  end
end
