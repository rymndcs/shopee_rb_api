# frozen_string_literal: true

module ShopeeRbApi
  # Shared plumbing for the resource classes. Not part of the public contract.
  module Resources
    # Identity arguments accept a String or an Integer; Shopee's wire type is an integer.
    def self.integer_id(value, name)
      Integer(value.to_s, 10)
    rescue ArgumentError
      raise ArgumentError, "#{name} must be an integer id, got #{value.inspect}"
    end

    # One shop session's signed calls, handed to every resource so the resources never see the token directly.
    class Session
      include Redaction

      attr_reader :connection

      def initialize(connection, access_token:, shop_id:)
        @connection = connection
        @auth = { access_token:, shop_id: }.freeze
        freeze
      end

      def get(path, query = {})
        @connection.call(:get, path, query:, auth: @auth)
      end

      def post(path, body, idempotent: false)
        @connection.call(:post, path, body:, auth: @auth, idempotent:)
      end

      def request(http_method, path, query:, body:, idempotent:)
        @connection.call(http_method, path, query:, body:, auth: @auth, idempotent:)
      end

      # A Public-type call (partner-signed only) made from a shop session, e.g. media_space/upload_image.
      def public_post(path, body, content_type:)
        @connection.call(:post, path, body:, content_type:)
      end

      def inspect
        "#<#{self.class.name} shop_id=#{@auth[:shop_id]} access_token=#{Redaction::REDACTED}>"
      end
    end

    class Base
      def initialize(session)
        @session = session
        freeze
      end

      def inspect
        "#<#{self.class.name}>"
      end

      private

      attr_reader :session

      def id!(value, name)
        Resources.integer_id(value, name)
      end

      def ids!(values, name, max)
        list = Array(values).map { |v| id!(v, name) }
        raise ArgumentError, "#{name} is empty" if list.empty?
        raise ArgumentError, "#{name} has #{list.size} ids; the maximum per call is #{max}" if list.size > max

        list
      end

      def page_size!(value, max)
        size = value.nil? ? max : Integer(value)
        raise ArgumentError, "page_size must be between 1 and #{max}, got #{size}" unless size.between?(1, max)

        size
      end

      def batch!(list, name, max)
        list = Array(list)
        raise ArgumentError, "#{name} is empty" if list.empty?
        raise ArgumentError, "#{name} has #{list.size} entries; the maximum per call is #{max}" if list.size > max

        list
      end

      def stringify(hash)
        (hash || {}).to_h.transform_keys(&:to_s)
      end

      # A Page from one Shopee response. `items_key` names the list inside `data`.
      def page(response, items_key, next_cursor, total = nil)
        Page.new(items: Array(response.data[items_key]).freeze, next_cursor:, total:, response:)
      end

      # Shopee's int offset style: has_next_page + next_offset (get_item_list, get_brand_list).
      def offset_cursor(data)
        data["has_next_page"] == true && !data["next_offset"].nil? ? data["next_offset"].to_s : nil
      end
    end
  end
  private_constant :Resources
end
