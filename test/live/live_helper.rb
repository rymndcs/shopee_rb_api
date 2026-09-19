# frozen_string_literal: true

require "test_helper"
require "date"
require "fileutils"
require "logger"

# Opt-in live tests: `rake test:live`. They never run under plain `rake`, and they skip unless credentials are set.
#
#   Sandbox (preferred): SHOPEE_SANDBOX_PARTNER_ID, SHOPEE_SANDBOX_PARTNER_KEY, SHOPEE_SANDBOX_SHOP_ID,
#                        SHOPEE_SANDBOX_ACCESS_TOKEN              (endpoint defaults to :sandbox)
#   Live:                SHOPEE_LIVE_PARTNER_ID, SHOPEE_LIVE_PARTNER_KEY, SHOPEE_LIVE_SHOP_ID,
#                        SHOPEE_LIVE_ACCESS_TOKEN                 (endpoint defaults to :sg)
#   Either set may add   <PREFIX>_ENDPOINT (a name from ShopeeRbApi::ENDPOINTS) and <PREFIX>_BASE_URL.
#   SHOPEE_RECORD=1      writes every successful response (2xx, empty `error`), redacted, over
#                        test/fixtures/<endpoint>.json with "_source": "recorded live <date>", replacing the
#                        documentation sample. Error responses are never recorded.
#
# The live tests only READ. They never refresh a token (Shopee refresh tokens are single use) and never write.
module LiveHelper
  PREFIXES = { "SHOPEE_SANDBOX" => :sandbox, "SHOPEE_LIVE" => :sg }.freeze
  REQUIRED = %w[PARTNER_ID PARTNER_KEY SHOP_ID ACCESS_TOKEN].freeze
  SECRET_KEYS = /token|secret|partner_key|\Asign\z|resend_code|\Acode\z/i
  # Path => fixture name, where the fixture is named after the doc api_name rather than the path.
  FIXTURE_NAMES = { "product_get_variation_tree" => "product_get_variations" }.freeze

  module_function

  def prefix
    PREFIXES.keys.find { |p| REQUIRED.all? { |k| !ENV.fetch("#{p}_#{k}", "").empty? } }
  end

  def env(key)
    ENV.fetch("#{prefix}_#{key}", nil)
  end

  def credentials
    REQUIRED.map { |k| env(k) }
  end

  def client
    options = { endpoint: (env("ENDPOINT") || PREFIXES.fetch(prefix)).to_sym }
    options[:base_url] = env("BASE_URL") if env("BASE_URL")
    logger = Logger.new($stderr, level: ENV["SHOPEE_LIVE_DEBUG"] ? Logger::DEBUG : Logger::INFO)
    ShopeeRbApi::Client.new(app_key: env("PARTNER_ID"), app_secret: env("PARTNER_KEY"), transport:, logger:, **options)
  end

  def shop
    client.shop(access_token: env("ACCESS_TOKEN"), shop_id: env("SHOP_ID"))
  end

  def transport
    net = ShopeeRbApi::Transport::NetHttp.new
    ENV["SHOPEE_RECORD"] == "1" ? Recorder.new(net, secrets: credentials, label: "#{prefix} #{env("ENDPOINT")}") : net
  end

  # Wraps a transport and records each response as a redacted fixture.
  class Recorder
    def initialize(inner, secrets:, label:, dir: Fixtures::DIR)
      @inner = inner
      @dir = dir
      @secrets = secrets.compact.reject(&:empty?)
      @label = label.strip
    end

    def call(method:, url:, headers:, body:)
      result = @inner.call(method:, url:, headers:, body:)
      record(URI(url).path, result)
      result
    end

    private

    def record(path, result)
      parsed = JSON.parse(result[:body])
      return unless recordable?(result[:status], parsed)

      name = path.delete_prefix("/api/v2/").tr("/", "_")
      name = FIXTURE_NAMES.fetch(name, name)
      fixture = { "_source" => { "url" => path, "pulled" => Date.today.iso8601,
                                 "origin" => "recorded live #{Date.today.iso8601} (#{@label}), redacted" },
                  "status" => result[:status], "headers" => {}, "body" => redact(parsed) }
      File.write(File.join(@dir, "#{name}.json"), "#{JSON.pretty_generate(fixture)}\n")
    rescue JSON::ParserError
      nil
    end

    def recordable?(status, parsed)
      (200..299).cover?(status.to_i) && parsed.is_a?(Hash) && parsed["error"].to_s.empty?
    end

    def redact(value)
      case value
      when Hash then value.to_h { |k, v| [k, redact_member(k, v)] }
      when Array then value.map { |v| redact(v) }
      when String then @secrets.reduce(value) { |text, secret| text.gsub(secret, "[REDACTED]") }
      else value
      end
    end

    def redact_member(key, value)
      key.to_s.match?(SECRET_KEYS) && value.is_a?(String) ? "[REDACTED]" : redact(value)
    end
  end

  # Include in a live test class: every test skips unless a credential set is present.
  module Gate
    def setup
      super
      return if LiveHelper.prefix

      skip "set SHOPEE_SANDBOX_* or SHOPEE_LIVE_* to run live tests (see test/live/live_helper.rb)"
    end
  end
end
