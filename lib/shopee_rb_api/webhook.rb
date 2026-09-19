# frozen_string_literal: true

module ShopeeRbApi
  # Shopee push (webhook) verification and parsing: pure functions, no HTTP.
  # https://open.shopee.com/developer-guide/18
  #
  # The signature is HMAC-SHA256(partner_key, url + "|" + raw_body), hex-encoded, sent in the Authorization header.
  # `url` is the exact callback URL registered in the console, which behind a proxy is not always the URL the app
  # sees. Hash the raw body as received, never re-serialized JSON. The receiver must answer 2xx with an EMPTY body,
  # or Shopee counts a failure and eventually disables the subscription.
  module Webhook
    TYPES = { "12" => :authorization_expiring, "2" => :deauthorized }.freeze

    module_function

    # => true | false. app_key is accepted for the shared interface; Shopee's base string does not use it.
    def verify(raw_body:, signature:, app_key:, app_secret:, url: nil)
      _ = app_key
      raise ArgumentError, "url: is required: Shopee signs the callback URL with the body" if url.nil?
      return false unless signature.is_a?(String) && raw_body.is_a?(String)

      expected = Signer.sign(app_secret, Signer.push_base_string(url, raw_body))
      given = signature.downcase
      given.bytesize == expected.bytesize && OpenSSL.fixed_length_secure_compare(expected, given)
    end

    # => WebhookEvent. Raises ArgumentError when the body is not a JSON object.
    def parse(raw_body)
      raw = JSON.parse(raw_body.to_s)
      raise ArgumentError, "webhook body is not a JSON object" unless raw.is_a?(Hash)

      event(Envelope.deep_freeze(raw))
    rescue JSON::ParserError
      raise ArgumentError, "webhook body is not valid JSON"
    end

    def event(raw)
      code = raw["code"].to_s
      WebhookEvent.new(type: TYPES.fetch(code, :other), code:, shop_id: raw["shop_id"]&.to_s,
                       occurred_at: raw["timestamp"].is_a?(Integer) ? Time.at(raw["timestamp"]).utc : nil,
                       data: raw["data"].is_a?(Hash) ? raw["data"] : {}.freeze, raw:)
    end
    private_class_method :event
  end
end
