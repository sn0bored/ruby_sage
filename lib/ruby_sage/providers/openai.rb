# frozen_string_literal: true

module RubySage
  module Providers
    # Provider shell for OpenAI chat integration.
    class OpenAI < Base
      # @see RubySage::Providers::Base#chat
      def chat(system_prompt:, cached_context:, messages:)
        raise NotImplementedError
      end
    end
  end
end
