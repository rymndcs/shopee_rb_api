# frozen_string_literal: true

module ShopeeRbApi
  # Stamps, signs, sends, parses and classifies one request. Each retry under an opt-in RetryPolicy goes through
  # #perform again, so it is re-stamped from the injected clock and re-signed.
  class Connection
    include Redaction

    HTTP_METHODS = %i[get post put delete].freeze
    NETWORK_ERRORS = Transport::NetHttp::NETWORK_ERRORS
    USER_AGENT = "shopee_rb_api/#{VERSION} (Ruby #{RUBY_VERSION})".freeze

    attr_reader :partner_id, :base_url, :auth_base_url

    def initialize(partner_id:, partner_key:, base_url:, auth_base_url:, transport:, clock:, logger:, retry_policy:)
      @partner_id = partner_id
      @partner_key = partner_key
      @base_url = base_url
      @auth_base_url = auth_base_url
      @transport = transport
      @clock = clock
      @logger = logger
      @retry_policy = retry_policy
      freeze
    end

    # The current Time from the injected clock: the only time source for signing and expiries.
    def now
      @clock.call
    end

    # auth: nil for a Public call, or { access_token:, shop_id: } for a Shop call.
    # body: a Hash or Array is sent as JSON; a String is sent verbatim with content_type:.
    def call(http_method, path, query: nil, body: nil, content_type: nil, auth: nil, idempotent: nil)
      raise ArgumentError, "unknown HTTP method #{http_method.inspect}" unless HTTP_METHODS.include?(http_method)
      raise ArgumentError, "path must start with /" unless path.to_s.start_with?("/")

      idempotent = http_method == :get if idempotent.nil?
      payload, type = encode_body(body, content_type)
      @retry_policy.run do
        perform(http_method, path.to_s, query:, body: payload, content_type: type, auth:, idempotent:)
      end
    end

    def inspect
      "#<#{self.class.name} partner_id=#{@partner_id} base_url=#{@base_url} partner_key=#{Redaction::REDACTED}>"
    end

    private

    def perform(http_method, path, query:, body:, content_type:, auth:, idempotent:)
      time = now
      url = "#{@base_url}#{path}?#{URI.encode_www_form(signed_query(path, time.to_i, auth).merge(compact(query)))}"
      headers = { "User-Agent" => USER_AGENT, "Accept" => "application/json" }
      headers["Content-Type"] = content_type if content_type
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = send_request(http_method, url, headers, body, idempotent)
      log(http_method, path, result, started)
      Envelope.build(result, endpoint: path, idempotent:, now: time)
    end

    def signed_query(path, timestamp, auth)
      common = { "partner_id" => @partner_id, "timestamp" => timestamp }
      if auth
        common["access_token"] = auth.fetch(:access_token)
        common["shop_id"] = auth.fetch(:shop_id)
      end
      base = Signer.base_string(partner_id: @partner_id, path:, timestamp:, access_token: common["access_token"],
                                shop_id: common["shop_id"])
      common.merge("sign" => Signer.sign(@partner_key, base))
    end

    def send_request(http_method, url, headers, body, idempotent)
      @transport.call(method: http_method, url:, headers:, body:)
    rescue TransportError, *NETWORK_ERRORS => e
      raise TransportError.new(e.message, idempotent:)
    end

    def encode_body(body, content_type)
      case body
      when nil then [nil, nil]
      when String then [body, content_type || "application/json"]
      else [JSON.generate(body), "application/json"]
      end
    end

    def compact(query)
      (query || {}).each_with_object({}) { |(k, v), out| out[k.to_s] = v unless v.nil? }
    end

    def log(http_method, path, result, started)
      return unless @logger

      ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      request_id = Envelope.parse(result[:body])&.fetch("request_id", nil)
      @logger.debug("shopee_rb_api #{http_method.upcase} #{path} status=#{result[:status]} " \
                    "request_id=#{request_id} duration_ms=#{ms}")
    end
  end
  private_constant :Connection
end
