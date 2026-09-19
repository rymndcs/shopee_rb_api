# frozen_string_literal: true

module ShopeeRbApi
  # Shopee request signing (https://open.shopee.com/developer-guide/16): lower-case hex HMAC-SHA256, keyed with the
  # partner_key string, over a plain concatenation in a fixed order, with no separators and no sorting:
  #   Shop:     partner_id + path + timestamp + access_token + shop_id
  #   Merchant: partner_id + path + timestamp + access_token + merchant_id
  #   Public:   partner_id + path + timestamp
  # The request body and business parameters are not signed.
  #
  # Push verification (https://open.shopee.com/developer-guide/18): HMAC-SHA256 over url + "|" + raw body.
  module Signer
    module_function

    def base_string(partner_id:, path:, timestamp:, access_token: nil, shop_id: nil, merchant_id: nil)
      "#{partner_id}#{path}#{timestamp}#{access_token}#{shop_id || merchant_id}"
    end

    def sign(key, base_string)
      OpenSSL::HMAC.hexdigest("SHA256", key.to_s, base_string)
    end

    def push_base_string(url, raw_body)
      "#{url.to_s.b}|#{raw_body.to_s.b}".b
    end
  end
  private_constant :Signer
end
