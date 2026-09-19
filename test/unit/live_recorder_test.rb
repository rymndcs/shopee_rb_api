# frozen_string_literal: true

# One recording, several properties of the written fixture.
# rubocop:disable Minitest/MultipleAssertions

require_relative "unit_helper"
require_relative "../live/live_helper"
require "tmpdir"

# The live recorder, offline: it must write a redacted fixture that names its source.
class LiveRecorderTest < Minitest::Test
  def test_records_a_redacted_fixture_naming_its_source
    Dir.mktmpdir do |dir|
      body = { "error" => "", "request_id" => "r", "access_token" => "tok-123", "response" => { "note" => "k=sekret" } }
      inner = FakeTransport.new(FakeTransport.json(body))
      recorder = LiveHelper::Recorder.new(inner, secrets: %w[sekret], label: "SHOPEE_SANDBOX sandbox", dir:)
      recorder.call(method: :get, url: "https://h.test/api/v2/product/get_variation_tree?sign=abc", headers: {},
                    body: nil)
      fixture = JSON.parse(File.read(File.join(dir, "product_get_variations.json")))

      assert_match(/\Arecorded live \d{4}-\d{2}-\d{2} \(SHOPEE_SANDBOX sandbox\), redacted\z/,
                   fixture["_source"]["origin"])
      assert_equal "/api/v2/product/get_variation_tree", fixture["_source"]["url"]
      assert_equal "[REDACTED]", fixture["body"]["access_token"]
      assert_equal "k=[REDACTED]", fixture["body"]["response"]["note"]
      refute_includes File.read(File.join(dir, "product_get_variations.json")), "abc"
    end
  end

  # Captain decision 2026-09-20: order responses carry real customers' data, so they are never written, even when
  # they succeed. Orders stay on documentation samples.
  def test_order_responses_are_never_recorded
    Dir.mktmpdir do |dir|
      responses = %w[order_get_order_list order_get_order_detail order_get_order_detail].map do |name|
        Fixtures.response(name)
      end
      recorder = LiveHelper::Recorder.new(FakeTransport.new(*responses), secrets: [], label: "SHOPEE_SANDBOX", dir:)
      %w[get_order_list get_order_detail search_package_list].each do |name|
        recorder.call(method: :get, url: "https://h.test/api/v2/order/#{name}?sign=abc", headers: {}, body: nil)
      end

      assert_empty Dir.children(dir)
    end
  end

  def test_customer_personal_data_is_redacted_in_other_responses
    Dir.mktmpdir do |dir|
      response = { "shop_id" => 10, "Email" => "a@b.test", "phone2" => "61****7", "buyer_username" => "hh",
                   "shop_name" => "Ha", "nickName" => "hh", "address1" => "1 Changi Village Road",
                   "addressDetail" => { "city" => "SG" }, "recipient_info" => { "zipcode" => "0123" },
                   "buyer" => ["x"], "status" => "NORMAL" }
      inner = FakeTransport.new(FakeTransport.json({ "error" => "", "request_id" => "r", "response" => response }))
      recorder = LiveHelper::Recorder.new(inner, secrets: [], label: "SHOPEE_SANDBOX", dir:)
      recorder.call(method: :get, url: "https://h.test/api/v2/shop/get_shop_info", headers: {}, body: nil)
      body = JSON.parse(File.read(File.join(dir, "shop_get_shop_info.json")))["body"]["response"]

      assert_equal({ "shop_id" => 10, "status" => "NORMAL" }, body.reject { |_, v| v == "[REDACTED]" })
      assert_equal 11, body.size
      refute_includes JSON.generate(body), "Changi"
    end
  end

  def test_error_responses_never_replace_a_fixture
    Dir.mktmpdir do |dir|
      refusal = { "error" => "warehouse.error_not_in_whitelist", "message" => "Not whitelisted.", "request_id" => "r" }
      inner = FakeTransport.new(FakeTransport.json(refusal), FakeTransport.json({ "error" => "" }, status: 500))
      recorder = LiveHelper::Recorder.new(inner, secrets: [], label: "SHOPEE_SANDBOX", dir:)
      2.times do
        recorder.call(method: :get, url: "https://h.test/api/v2/shop/get_warehouse_detail", headers: {}, body: nil)
      end

      assert_empty Dir.children(dir)
    end
  end
end
# rubocop:enable Minitest/MultipleAssertions
