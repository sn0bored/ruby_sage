# frozen_string_literal: true

require "ruby_sage/mcp/tools/base"

module RubySage
  module MCP
    module Tools
      # Searches exact class and method names in artifact signatures.
      class SearchSymbols < Base
        NAME = "search_symbols"
        DESCRIPTION = "Search exact class and method names in RubySage signatures."
        INPUT_SCHEMA = {
          "type" => "object",
          "properties" => {
            "name" => {
              "type" => "string",
              "description" => "Exact class or method name to find."
            },
            "kind" => {
              "type" => "string",
              "enum" => %w[class method any],
              "description" => "Restrict matches to classes, methods, or any symbol."
            }
          },
          "required" => ["name"],
          "additionalProperties" => false
        }.freeze

        # @param arguments [Hash] tool arguments.
        # @return [Array<Hash>] exact symbol matches.
        def call(arguments)
          name = require_string(arguments, "name")
          kind = value_for(arguments, "kind") || "any"
          raise ArgumentError, "kind must be `class`, `method`, or `any`" unless %w[class method any].include?(kind)

          disk_store.each_artifact.flat_map do |payload|
            symbol_hits(payload, name, kind)
          end
        end

        private

        def symbol_hits(payload, name, kind)
          hits = []
          hits.concat(class_hits(payload, name)) if %w[class any].include?(kind)
          hits.concat(method_hits(payload, name)) if %w[method any].include?(kind)
          hits
        end

        def class_hits(payload, name)
          signature_classes(payload).filter_map do |entry|
            symbol_hit(payload, "class", value_for(entry, :name)) if value_for(entry, :name) == name
          end
        end

        def method_hits(payload, name)
          signature_methods(payload).filter_map do |entry|
            symbol_hit(payload, "method", value_for(entry, :name)) if value_for(entry, :name) == name
          end
        end

        def symbol_hit(payload, kind, symbol)
          {
            "path" => value_for(payload, :path),
            "kind" => kind,
            "symbol" => symbol
          }
        end
      end
    end
  end
end
