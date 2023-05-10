# frozen_string_literal: true

# Stripe Ruby bindings
# API spec at https://stripe.com/docs/api
require "cgi"
require "json"
require "logger"
require "net/http"
require "openssl"
require "rbconfig"
require "securerandom"
require "set"
require "socket"
require "uri"
require "forwardable"
require "base64"

# Version
require "stripe/api_version"
require "stripe/version"

# API operations
require "stripe/api_operations/create"
require "stripe/api_operations/delete"
require "stripe/api_operations/list"
require "stripe/api_operations/nested_resource"
require "stripe/api_operations/request"
require "stripe/api_operations/save"
require "stripe/api_operations/search"

# API resource support classes
require "stripe/errors"
require "stripe/object_types"
require "stripe/util"
require "stripe/connection_manager"
require "stripe/multipart_encoder"
require "stripe/stripe_client"
require "stripe/stripe_object"
require "stripe/stripe_response"
require "stripe/list_object"
require "stripe/search_result_object"
require "stripe/error_object"
require "stripe/api_resource"
require "stripe/api_resource_test_helpers"
require "stripe/singleton_api_resource"
require "stripe/webhook"
require "stripe/stripe_configuration"
require "stripe/request_signing_authenticator"

# Named API resources
require "stripe/resources"

# OAuth
require "stripe/oauth"

module Stripe
  DEFAULT_CA_BUNDLE_PATH = __dir__ + "/data/ca-certificates.crt"

  # map to the same values as the standard library's logger
  LEVEL_DEBUG = Logger::DEBUG
  LEVEL_ERROR = Logger::ERROR
  LEVEL_INFO = Logger::INFO

  @app_info = nil

  @config = Stripe::StripeConfiguration.setup

  class << self
    extend Forwardable

    attr_reader :config

    # User configurable options
    def_delegators :@config, :api_key, :api_key=
    def_delegators :@config, :authenticator, :authenticator=
    def_delegators :@config, :api_version, :api_version=
    def_delegators :@config, :stripe_account, :stripe_account=
    def_delegators :@config, :api_base, :api_base=
    def_delegators :@config, :uploads_base, :uploads_base=
    def_delegators :@config, :connect_base, :connect_base=
    def_delegators :@config, :open_timeout, :open_timeout=
    def_delegators :@config, :read_timeout, :read_timeout=
    def_delegators :@config, :write_timeout, :write_timeout=
    def_delegators :@config, :proxy, :proxy=
    def_delegators :@config, :verify_ssl_certs, :verify_ssl_certs=
    def_delegators :@config, :ca_bundle_path, :ca_bundle_path=
    def_delegators :@config, :log_level, :log_level=
    def_delegators :@config, :logger, :logger=
    def_delegators :@config, :max_network_retries, :max_network_retries=
    def_delegators :@config, :enable_telemetry=, :enable_telemetry?
    def_delegators :@config, :client_id=, :client_id

    # Internal configurations
    def_delegators :@config, :max_network_retry_delay
    def_delegators :@config, :initial_network_retry_delay
    def_delegators :@config, :ca_store
  end

  # Gets the application for a plugin that's identified some. See
  # #set_app_info.
  def self.app_info
    @app_info
  end

  def self.app_info=(info)
    @app_info = info
  end

  # Sets some basic information about the running application that's sent along
  # with API requests. Useful for plugin authors to identify their plugin when
  # communicating with Stripe.
  #
  # Takes a name and optional partner program ID, plugin URL, and version.
  def self.set_app_info(name, partner_id: nil, url: nil, version: nil)
    @app_info = {
      name: name,
      partner_id: partner_id,
      url: url,
      version: version,
    }
  end

  class Preview
    def self._get_default_opts(opts)
      { stripe_version: ApiVersion::PREVIEW, api_mode: :preview }.merge(opts)
    end

    def self.get(url, opts = {})
      Stripe.raw_request(:get, url, {}, _get_default_opts(opts))
    end

    def self.post(url, params = {}, opts = {})
      Stripe.raw_request(:post, url, params, _get_default_opts(opts))
    end

    def self.delete(url, opts = {})
      Stripe.raw_request(:delete, url, {}, _get_default_opts(opts))
    end
  end

  class RawRequest
    include Stripe::APIOperations::Request

    def initialize
      @opts = {}
    end

    def execute(method, url, params = {}, opts = {})
      resp, = execute_resource_request(method, url, params, opts)

      resp
    end
  end

  # Sends a request to Stripe REST API
  def self.raw_request(method, url, params = {}, opts = {})
    req = RawRequest.new
    req.execute(method, url, params, opts)
  end

  def self.deserialize(data)
    data = JSON.parse(data) if data.is_a?(String)
    Util.convert_to_stripe_object(data, {})
  end
end

Stripe.log_level = ENV["STRIPE_LOG"] unless ENV["STRIPE_LOG"].nil?
