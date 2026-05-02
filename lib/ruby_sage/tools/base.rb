# frozen_string_literal: true

module RubySage
  module Tools
    # @abstract Subclass and implement {.name}, {.description}, {.input_schema},
    #   and {#call} to add a new tool the +:admin+ chat loop can use.
    class Base
      # Tool identifier the provider returns inside +tool_use+ blocks.
      #
      # @return [String]
      def self.name
        raise NotImplementedError
      end

      # Plain-language description of what the tool does. Shown to the model
      # so it can decide when to call the tool.
      #
      # @return [String]
      def self.description
        raise NotImplementedError
      end

      # JSON Schema describing the tool's input.
      #
      # @return [Hash]
      def self.input_schema
        raise NotImplementedError
      end

      # Returns the provider-shaped tool definition for Anthropic.
      #
      # @return [Hash]
      def self.to_anthropic
        {
          "name" => name,
          "description" => description,
          "input_schema" => input_schema
        }
      end

      # Executes the tool against the given input.
      #
      # @param input [Hash] parameters the model passed in the +tool_use+ block.
      # @return [Hash] result body the loop will JSON-encode for the provider.
      def call(input:)
        raise NotImplementedError
      end
    end
  end
end
