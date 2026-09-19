# frozen_string_literal: true

module ShopeeRbApi
  # One Client per app credential (Shopee partner_id + partner_key). Immutable and safe to share across threads.
  # There is no global configuration.
  class Client
    include Redaction

    attr_reader :app_key, :endpoint, :auth

    # app_key:       Shopee partner_id (String or Integer).
    # app_secret:    Shopee partner_key.
    # endpoint:      a Symbol from ShopeeRbApi::ENDPOINTS; it names both the API host and the auth page host.
    # base_url:      any API host URL; overrides the endpoint's API host.
    # auth_base_url: any auth page host URL; overrides the endpoint's auth host.
    # transport:     any object with #call(method:, url:, headers:, body:) -> { status:, headers:, body: }.
    # clock:         returns a Time; the only time source for signing and expiries.
    # logger:        any Logger; debug lines only, and never a secret.
    # retry_policy:  RetryPolicy.none (default) or an opt-in RetryPolicy.new(...).
    def initialize(app_key:, app_secret:, endpoint: Endpoints::DEFAULT, base_url: nil, auth_base_url: nil,
                   transport: Transport::NetHttp.new, clock: -> { Time.now }, logger: nil,
                   retry_policy: RetryPolicy.none)
      @app_key = partner_id!(app_key).to_s
      @endpoint = endpoint
      hosts = hosts!(endpoint)
      @connection = Connection.new(
        partner_id: Integer(@app_key), partner_key: secret!(app_secret),
        base_url: url!(base_url || hosts[:api], "base_url"), auth_base_url: url!(auth_base_url || hosts[:auth], "auth_base_url"),
        transport: callable!(transport, "transport"), clock: callable!(clock, "clock"), logger:,
        retry_policy: retry_policy || RetryPolicy.none
      )
      @auth = Auth.new(@connection)
      freeze
    end

    # A shop session. Shopee's locator is { shop_id: }.
    def shop(access_token:, **locator)
      missing = Shop::LOCATOR_KEYS - locator.keys
      unknown = locator.keys - Shop::LOCATOR_KEYS
      raise ArgumentError, "missing locator key(s) #{missing.inspect}" if missing.any?
      raise ArgumentError, "unknown locator key(s) #{unknown.inspect}" if unknown.any?

      Shop.new(@connection, access_token:, **locator)
    end

    # GET /api/v2/public/get_shops_by_partner (Public, page_no paged): every shop authorized to this app, with its
    # authorization deadline. The access token is not used on Shopee. => Pager of AuthorizedShop
    # https://open.shopee.com/documents/v2/v2.public.get_shops_by_partner?module=104&type=1
    def authorized_shops(access_token: nil)
      _ = access_token
      Pager.new do |page_no|
        response = @connection.call(:get, Endpoints::SHOPS_BY_PARTNER, query: { page_no: Integer(page_no || 1) })
        shops = Array(response.data["authed_shop_list"]).map { |raw| authorized_shop(raw) }
        more = response.data["more"] == true && shops.any?
        Page.new(items: shops.freeze, next_cursor: more ? (Integer(page_no || 1) + 1).to_s : nil, total: nil,
                 response:)
      end
    end

    # Verifies a Shopee push with this client's partner_key, then parses it. url: is the callback URL registered in
    # the console. Raises WebhookSignatureError when verification fails.
    def verify_webhook(raw_body:, signature:, url: nil)
      valid = Webhook.verify(raw_body:, signature:, app_key: @app_key, app_secret: @app_secret, url:)
      raise WebhookSignatureError, "Shopee push signature did not verify" unless valid

      Webhook.parse(raw_body)
    end

    # The escape hatch for app-level (Public-type) paths, partner-signed. One call, one request.
    def request(http_method, path, query: nil, body: nil, idempotent: nil)
      @connection.call(http_method, path, query:, body:, idempotent:)
    end

    def inspect
      "#<#{self.class.name} app_key=#{@app_key.inspect} endpoint=#{@endpoint.inspect} " \
        "app_secret=#{Redaction::REDACTED}>"
    end

    private

    def authorized_shop(raw)
      id = raw["shop_id"].to_s
      expire = raw["expire_time"]
      AuthorizedShop.new(shop_id: id, name: nil, region: raw["region"]&.to_s&.upcase,
                         authorization_expires_at: expire.is_a?(Integer) ? Time.at(expire).utc : nil,
                         locator: { shop_id: id }.freeze, raw:)
    end

    def partner_id!(value)
      Integer(value.to_s, 10)
    rescue ArgumentError
      raise ConfigurationError, "app_key must be the Shopee partner_id (an integer)"
    end

    def secret!(value)
      raise ConfigurationError, "app_secret must be a non-empty String" unless value.is_a?(String) && !value.empty?

      @app_secret = value
    end

    def hosts!(endpoint)
      ENDPOINTS.fetch(endpoint) do
        raise ConfigurationError, "unknown endpoint #{endpoint.inspect}; expected one of #{ENDPOINTS.keys.inspect} " \
                                  "(or pass base_url: / auth_base_url:)"
      end
    end

    def url!(value, name)
      uri = URI.parse(value.to_s)
      raise ConfigurationError, "#{name} must be an http(s) URL" unless %w[http https].include?(uri.scheme) && uri.host

      value.to_s.chomp("/")
    rescue URI::InvalidURIError
      raise ConfigurationError, "#{name} must be an http(s) URL"
    end

    def callable!(value, name)
      raise ConfigurationError, "#{name} must respond to #call" unless value.respond_to?(:call)

      value
    end
  end
end
