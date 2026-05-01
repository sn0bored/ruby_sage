# frozen_string_literal: true

module RubySage
  module Providers
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
      # @return [Hash] response with :answer, :citations, and :usage keys.
      # @raise [NotImplementedError]
      def chat(system_prompt:, cached_context:, messages:)
        raise NotImplementedError
      end
    end
  end
end
