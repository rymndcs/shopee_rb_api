# frozen_string_literal: true

module ShopeeRbApi
  # Every non-paged call returns a Response. `data` is the platform payload verbatim with the envelope removed;
  # `raw` is the parsed body exactly as received. Both are deeply frozen.
  Response = Data.define(:data, :request_id, :warnings, :item_errors, :http_status, :endpoint, :raw)

  # Turns Shopee's envelope into a Response, or raises the classified ApiError.
  #
  # The envelope is not uniform (https://open.shopee.com/developer-guide/16): the payload sits under `response` on
  # most endpoints, under `data` on get_variation_tree, and at top level on the auth, public and get_shop_info
  # endpoints. `error` is "" on success; `warning` flags a degraded success.
  module Envelope
    ENVELOPE_KEYS = %w[error message warning request_id msg debug_message].freeze
    UTC8 = 8 * 3600

    module_function

    # What an error needs besides the body: where the call went, whether it was idempotent, the response headers
    # and the time it was stamped.
    Call = Data.define(:endpoint, :idempotent, :headers, :now)

    def build(result, endpoint:, idempotent:, now:)
      status = result.fetch(:status).to_i
      call = Call.new(endpoint:, idempotent:, headers: result[:headers] || {}, now:)
      parsed = parse(result[:body])
      raise http_error(status, call) if parsed.nil?

      response = to_response(parsed, status, endpoint)
      error = parsed["error"].to_s
      raise api_error(error, parsed, response, call) unless error.empty?
      raise http_error(status, call, response) if status >= 400

      response
    end

    def parse(body)
      parsed = JSON.parse(body.to_s)
      parsed.is_a?(Hash) ? parsed : nil
    rescue JSON::ParserError
      nil
    end

    def to_response(parsed, status, endpoint)
      data = payload(parsed)
      Response.new(data: deep_freeze(data), request_id: parsed["request_id"]&.to_s, warnings: warnings(parsed),
                   item_errors: item_errors(data).freeze, http_status: status, endpoint:, raw: deep_freeze(parsed))
    end

    def payload(parsed)
      rest = parsed.except(*ENVELOPE_KEYS)
      if rest.key?("response")
        inner = rest.delete("response")
        # get_item_limit documents gtin_limit beside `response`; keep such siblings rather than drop them.
        # A null `response` (update_tier_variation answers with the envelope only) leaves the siblings, often {}.
        return inner if inner.is_a?(Array)

        inner.is_a?(Hash) ? rest.merge(inner) : rest
      elsif rest.key?("data") && rest.size == 1
        rest["data"]
      else
        rest
      end
    end

    def warnings(parsed)
      Array(parsed["warning"]).map(&:to_s).reject(&:empty?).freeze
    end

    # Shopee's per-item failures inside a success: failure_list (unlist, stock, price), failure_item_list
    # (diagnosis), item_list[].fail_error (violations) and image_info_list[].error (upload_image).
    def item_errors(data)
      return [] unless data.is_a?(Hash)

      failure_lists(data) + flagged(data["item_list"], "item_id", "fail_error", "fail_message") +
        flagged(data["image_info_list"], "id", "error", "message")
    end

    def failure_lists(data)
      (entries(data["failure_list"]) + entries(data["failure_item_list"])).map do |failure|
        item_error(failure["item_id"] || failure["model_id"], "", failure["failed_reason"], failure)
      end
    end

    def flagged(list, id_key, code_key, message_key)
      entries(list).reject { |entry| entry[code_key].to_s.empty? }.map do |entry|
        item_error(entry[id_key], entry[code_key], entry[message_key], entry)
      end
    end

    def entries(list)
      list.is_a?(Array) ? list.grep(Hash) : []
    end

    def item_error(id, code, message, raw)
      ItemError.new(id: id.to_s, code: code.to_s, message: message.to_s, raw: deep_freeze(raw))
    end

    def api_error(code, parsed, response, call)
      klass = ErrorTable.classify(code, parsed["message"] || parsed["msg"])
      message = parsed["message"].to_s.empty? ? code : parsed["message"].to_s
      klass.new(message, code:, request_id: response.request_id, http_status: response.http_status,
                         endpoint: call.endpoint, detail: [], response:, idempotent: call.idempotent,
                         retry_after: retry_after(klass, call))
    end

    def http_error(status, call, response = nil)
      klass = ErrorTable.classify_status(status)
      klass.new("HTTP #{status}", code: status.to_s, request_id: response&.request_id, http_status: status,
                                  endpoint: call.endpoint, detail: [], response:, idempotent: call.idempotent,
                                  retry_after: retry_after(klass, call))
    end

    def retry_after(klass, call)
      header = call.headers.find { |k, _| k.to_s.casecmp?("retry-after") }&.last
      from_header = parse_retry_after(Array(header).first, call.now)
      return from_header if from_header
      return seconds_to_utc8_midnight(call.now) if klass == QuotaExceededError

      nil
    end

    def parse_retry_after(value, now)
      return nil if value.nil? || value.to_s.strip.empty?
      return Float(value) if value.to_s.match?(/\A\s*\d+(\.\d+)?\s*\z/)

      [Time.httpdate(value.to_s) - now, 0.0].max
    rescue ArgumentError
      nil
    end

    # error_limit: "please try again after 00:00 (UTC+08:00)".
    def seconds_to_utc8_midnight(now)
      local = now.getlocal(UTC8)
      midnight = Time.new(local.year, local.month, local.day, 0, 0, 0, UTC8) + 86_400
      (midnight - now).to_f
    end

    def deep_freeze(value)
      case value
      when Hash then value.each_value { |v| deep_freeze(v) }.freeze
      when Array then value.each { |v| deep_freeze(v) }.freeze
      when String then value.freeze
      else value
      end
    end
  end
  private_constant :Envelope
end
