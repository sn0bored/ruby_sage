# frozen_string_literal: true

require "pathname"

require "ruby_sage/artifacts/disk_store"
require "ruby_sage/mcp/tools/find_relevant_files"
require "ruby_sage/mcp/tools/get_file_context"
require "ruby_sage/mcp/tools/get_route_handler"
require "ruby_sage/mcp/tools/index_status"
require "ruby_sage/mcp/tools/search_symbols"

module RubySage
  module MCP
    # Maps MCP tool names to handler classes and exposes MCP tool metadata.
    class ToolRegistry
      HANDLERS = [
        Tools::FindRelevantFiles,
        Tools::GetFileContext,
        Tools::GetRouteHandler,
        Tools::SearchSymbols,
        Tools::IndexStatus
      ].freeze

      # @param host_root [String, Pathname] root directory of the host app.
      # @param disk_store [RubySage::Artifacts::DiskStore, nil] disk store override.
      def initialize(host_root:, disk_store: nil)
        @host_root = Pathname(host_root).expand_path
        @disk_store = disk_store || Artifacts::DiskStore.new(host_root: @host_root)
      end

      # @return [Array<Hash>] MCP tool definitions for tools/list.
      def tool_definitions
        HANDLERS.map do |handler|
          {
            "name" => handler::NAME,
            "description" => handler::DESCRIPTION,
            "inputSchema" => handler::INPUT_SCHEMA
          }
        end
      end

      # Dispatches a tool call to its handler.
      #
      # @param name [String] MCP tool name.
      # @param arguments [Hash] tool arguments.
      # @return [Object] tool-specific result payload.
      # @raise [RubySage::MCP::ToolRegistry::UnknownTool]
      def call(name, arguments)
        handler = handler_for(name)
        raise UnknownTool, "Unknown tool: #{name}" if handler.nil?
        raise ArgumentError, "Tool arguments must be an object" unless arguments.is_a?(Hash)

        handler.new(host_root: host_root, disk_store: disk_store).call(arguments)
      end

      # Raised when a requested tool is not registered.
      class UnknownTool < StandardError; end

      private

      attr_reader :host_root, :disk_store

      def handler_for(name)
        HANDLERS.find { |handler| name == handler::NAME }
      end
    end
  end
end
