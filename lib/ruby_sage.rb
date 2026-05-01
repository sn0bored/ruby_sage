# frozen_string_literal: true

require "ruby_sage/version"
require "ruby_sage/configuration"
require "ruby_sage/providers/base"
require "ruby_sage/providers/anthropic"
require "ruby_sage/providers/openai"
require "ruby_sage/engine"

# RubySage exposes a Rails engine for scanning a host application and serving
# code-aware assistance.
#
# @example Configure RubySage from a host app initializer
#   RubySage.configure do |config|
#     config.provider = :anthropic
#     config.api_key = ENV["ANTHROPIC_API_KEY"]
#     config.auth_check = ->(controller) { controller.current_user&.admin? }
#     config.csp_nonce = ->(controller) { controller.request.content_security_policy_nonce }
#   end
module RubySage
  # Returns the process-wide RubySage configuration.
  #
  # @return [RubySage::Configuration]
  def self.configuration
    @configuration ||= Configuration.new
  end

  # Yields the process-wide configuration for host app setup.
  #
  # @yieldparam config [RubySage::Configuration]
  # @return [RubySage::Configuration]
  def self.configure
    yield configuration
    reset_provider!
    configuration
  end

  # Restores the default configuration and clears memoized runtime state.
  #
  # @return [RubySage::Configuration]
  def self.reset_configuration!
    @configuration = Configuration.new
    reset_provider!
    @configuration
  end

  # Returns an instance of the configured provider adapter.
  #
  # @return [RubySage::Providers::Base]
  # @raise [ArgumentError] when the configured provider is unknown.
  def self.provider
    @provider ||= case configuration.provider
                  when :anthropic then Providers::Anthropic.new(configuration)
                  when :openai then Providers::OpenAI.new(configuration)
                  else raise ArgumentError, "Unknown provider: #{configuration.provider}"
                  end
  end

  # Clears the memoized provider adapter.
  #
  # @return [nil]
  def self.reset_provider!
    @provider = nil
  end
end
