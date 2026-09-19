# frozen_string_literal: true

require_relative "helper"

module Conformance
  # Hosts are configuration, not code (CONTRACT.md "Hosts"): every named host is selectable, any URL can replace it,
  # and no host is spelled out anywhere in lib/ outside the ENDPOINTS table.
  class HostsTest < Minitest::Test
    include Support

    ROOT = File.expand_path("../..", __dir__)

    def read_url(**)
      client, transport = client_with(adapter.read_success_response, **)
      adapter.read_call.call(client, adapter.build_shop(client))
      [transport.requests.first.url, adapter.authorize(client)]
    end

    def test_each_named_endpoint_selects_its_api_and_auth_host
      gem_module::ENDPOINTS.each do |name, hosts|
        api_url, auth_url = read_url(endpoint: name)

        assert api_url.start_with?("#{hosts[:api]}/"), "#{name}: #{api_url}"
        assert auth_url.start_with?("#{hosts[:auth]}/"), "#{name}: #{auth_url}"
      end
    end

    def test_a_custom_url_replaces_each_host
      api_url, auth_url = read_url(base_url: "https://api.example.test/", auth_base_url: "https://consent.example.test")

      assert api_url.start_with?("https://api.example.test/"), "custom API host: #{api_url}"
      refute api_url.start_with?("https://api.example.test//"), api_url
      assert auth_url.start_with?("https://consent.example.test/"), "custom auth host: #{auth_url}"
    end

    def test_the_default_endpoint_is_a_named_endpoint
      client, = client_with

      assert_includes gem_module::ENDPOINTS.keys, client.endpoint
    end

    def test_unknown_endpoint_and_malformed_urls_are_configuration_errors
      assert_raises(gem_module::ConfigurationError) { client_with(endpoint: :nowhere) }
      assert_raises(gem_module::ConfigurationError) { client_with(base_url: "not a url") }
      assert_raises(gem_module::ConfigurationError) { client_with(auth_base_url: "ftp://example.test") }
    end

    def test_no_host_is_hardcoded_outside_the_endpoints_table
      table = File.join(ROOT, "lib", adapter.gem_name, "endpoints.rb")
      offenders = Dir[File.join(ROOT, "lib/**/*.rb")].reject { |f| f == table }.flat_map do |file|
        File.readlines(file).each_with_index.filter_map do |line, index|
          code = line.sub(/(^|\s)#.*$/, "")
          "#{file.delete_prefix("#{ROOT}/")}:#{index + 1}" if code.match?(%r{https?://})
        end
      end

      assert_empty offenders
    end
  end
end
