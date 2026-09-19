# frozen_string_literal: true

module ShopeeRbApi
  # Seller authorization and tokens (https://open.shopee.com/developer-guide/20).
  #
  # The gem stores no tokens and never refreshes on its own. A refresh token is SINGLE USE: persist both tokens of
  # the returned Grant in one write before doing anything else.
  class Auth
    include Redaction

    def initialize(connection)
      @connection = connection
      freeze
    end

    # => the seller authorization link on the configured auth host:
    #    <auth host>/auth?partner_id=..&auth_type=seller&redirect_uri=..&response_type=code[&state=..]
    # Shopee redirects back with code and shop_id (shop account) or main_account_id (main account).
    def authorize_url(redirect_uri: nil, state: nil)
      raise ArgumentError, "redirect_uri: is required" if redirect_uri.to_s.empty?

      query = { partner_id: @connection.partner_id, auth_type: "seller", redirect_uri: redirect_uri.to_s,
                response_type: "code" }
      query[:state] = state.to_s unless state.nil?
      "#{@connection.auth_base_url}#{Endpoints::AUTH_PAGE}?#{URI.encode_www_form(query)}"
    end

    # POST /api/v2/auth/token/get (Public). The code is single use and lives 10 minutes.
    # locator: exactly one of shop_id: or main_account_id:, as returned on the redirect.
    # https://open.shopee.com/documents/v2/v2.public.get_access_token?module=104&type=1
    def exchange_code(code:, **locator)
      raise ArgumentError, "code: is empty" if code.to_s.empty?

      body = { "code" => code.to_s, "partner_id" => @connection.partner_id }.merge(one_of!(locator, %i[shop_id main_account_id]))
      grant(@connection.call(:post, Endpoints::TOKEN_GET, body:))
    end

    # POST /api/v2/auth/access_token/get (Public). Returns a NEW refresh token; the old one is spent.
    # locator: exactly one of shop_id: or merchant_id:.
    # https://open.shopee.com/documents/v2/v2.public.refresh_access_token?module=104&type=1
    def refresh(refresh_token:, **locator)
      raise ArgumentError, "refresh_token: is empty" if refresh_token.to_s.empty?

      body = { "refresh_token" => refresh_token.to_s, "partner_id" => @connection.partner_id }
             .merge(one_of!(locator, %i[shop_id merchant_id]))
      grant(@connection.call(:post, Endpoints::TOKEN_REFRESH, body:))
    end

    # Extension. POST /api/v2/public/get_token_by_resend_code (Public; LIVE environment only): lost-token recovery
    # with the single-use resend code from the console. Shopee's request takes resend_code only, so no locator key
    # is accepted.
    # https://open.shopee.com/documents/v2/v2.public.get_token_by_resend_code?module=104&type=1
    def exchange_resend_code(resend_code:, **locator)
      raise ArgumentError, "resend_code: is empty" if resend_code.to_s.empty?
      raise ArgumentError, "unknown locator key(s) #{locator.keys.inspect}: Shopee takes resend_code only" if locator.any?

      grant(@connection.call(:post, Endpoints::TOKEN_BY_RESEND_CODE, body: { "resend_code" => resend_code.to_s }))
    end

    def inspect
      "#<#{self.class.name}>"
    end

    private

    def one_of!(locator, keys)
      unknown = locator.keys - keys
      raise ArgumentError, "unknown locator key(s) #{unknown.inspect}; expected one of #{keys.inspect}" if unknown.any?
      raise ArgumentError, "exactly one of #{keys.map { |k| "#{k}:" }.join(' or ')} is required" unless locator.size == 1

      key, value = locator.first
      { key.to_s => Resources.integer_id(value, key) }
    end

    def grant(response)
      data = response.data
      now = @connection.now
      Grant.new(
        access_token: data["access_token"].to_s, refresh_token: data["refresh_token"].to_s,
        # expire_in is documented as "the validity period of the access_token, in seconds".
        access_token_expires_at: data["expire_in"].nil? ? nil : (now + Integer(data["expire_in"])).utc,
        # Shopee documents a 30-day refresh token but returns no field for it; the gem does not hard-code it.
        refresh_token_expires_at: nil,
        shop_ids: ids(data, "shop_id_list", "shop_id"), merchant_ids: ids(data, "merchant_id_list", "merchant_id"),
        raw: response.raw
      )
    end

    def ids(data, list_key, key)
      list = data[list_key] || (data[key].nil? ? [] : [data[key]])
      Array(list).map(&:to_s).freeze
    end
  end
end
