# frozen_string_literal: true

module RubySage
  module Providers
    # Raised when an upstream LLM provider returns an error or malformed payload.
    class ProviderError < StandardError; end

    # @abstract Subclass and implement {#chat} to integrate a new LLM provider.
    class Base
      # Initializes a provider adapter.
      #
      # @param config [RubySage::Configuration]
      # @return [RubySage::Providers::Base]
      def initialize(config)
        @config = config
      end

      # Sends a chat request to the provider.
      #
      # @param system_prompt [String]
      # @param cached_context [String, nil] provider-specific cache marker may apply.
      # @param messages [Array<Hash>] each item contains :role and :content.
      # @param tools [Array<Hash>, nil] tool definitions in the provider's format.
      # @yield [String] each streamed chunk. V1 providers ignore the block.
      # @return [Hash] response with :answer, :citations, :usage, plus
      #   optionally :tool_calls, :stop_reason, :raw_content for tool-loop
      #   support.
      # @raise [NotImplementedError]
      def chat(system_prompt:, cached_context:, messages:, tools: nil, &_block)
        raise NotImplementedError
      end
    end
  end
end
