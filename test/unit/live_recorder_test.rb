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
end
# rubocop:enable Minitest/MultipleAssertions
