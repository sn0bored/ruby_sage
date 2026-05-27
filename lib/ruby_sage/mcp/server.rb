# frozen_string_literal: true

require "json"

require "ruby_sage/mcp/tool_registry"
require "ruby_sage/version"

module RubySage
  module MCP
    # Minimal MCP JSON-RPC 2.0 server over newline-delimited stdio.
    class Server
      PROTOCOL_VERSION = "2025-11-25"

      # @param host_root [String, Pathname] root directory of the host app.
      # @param input [IO] input stream carrying JSON-RPC messages.
      # @param output [IO] output stream for JSON-RPC responses.
      # @param registry [RubySage::MCP::ToolRegistry, nil] tool registry override.
      def initialize(host_root:, input: $stdin, output: $stdout, registry: nil)
        @input = input
        @output = output
        @registry = registry || ToolRegistry.new(host_root: host_root)
      end

      # Reads requests from stdin and writes JSON-RPC responses to stdout.
      #
      # @return [void]
      def run
        input.each_line do |line|
          response = response_for_line(line)
          write_response(response) unless response.nil?
        end
      end

      private

      attr_reader :input, :output, :registry

      def response_for_line(line)
        request = JSON.parse(line)
        return invalid_request_response(nil) unless request.is_a?(Hash)
        return nil if notification?(request)

        response_for_request(request)
      rescue JSON::ParserError
        error_response(nil, -32_700, "Parse error")
      end

      def response_for_request(request)
        id = request["id"]
        result = dispatch(request.fetch("method", nil), request.fetch("params", {}))
        success_response(id, result)
      rescue MethodNotFound => e
        error_response(id, -32_601, e.message)
      rescue InvalidParams, ToolRegistry::UnknownTool, ArgumentError => e
        error_response(id, -32_602, e.message)
      rescue StandardError => e
        error_response(id, -32_603, e.message)
      end

      def dispatch(method, params)
        case method
        when "initialize" then initialize_result(params)
        when "tools/list" then tools_list_result
        when "tools/call" then tools_call_result(params)
        else raise MethodNotFound, "Unknown method: #{method}"
        end
      end

      def initialize_result(params)
        {
          "protocolVersion" => protocol_version(params),
          "capabilities" => {
            "tools" => {
              "listChanged" => false
            }
          },
          "serverInfo" => {
            "name" => "ruby_sage",
            "title" => "RubySage",
            "version" => RubySage::VERSION
          }
        }
      end

      def protocol_version(params)
        return PROTOCOL_VERSION unless params.is_a?(Hash)

        params.fetch("protocolVersion", PROTOCOL_VERSION)
      end

      def tools_list_result
        {
          "tools" => registry.tool_definitions
        }
      end

      def tools_call_result(params)
        raise InvalidParams, "tools/call params must be an object" unless params.is_a?(Hash)

        name = params.fetch("name", nil)
        arguments = params.fetch("arguments", {})
        result = registry.call(name, arguments || {})
        tool_result(result)
      end

      def tool_result(result)
        {
          "content" => [
            {
              "type" => "text",
              "text" => JSON.pretty_generate(result)
            }
          ],
          "structuredContent" => {
            "result" => result
          },
          "isError" => false
        }
      end

      def notification?(request)
        !request.key?("id")
      end

      def write_response(response)
        output.write("#{JSON.generate(response)}\n")
        output.flush
      end

      def success_response(id, result)
        {
          "jsonrpc" => "2.0",
          "id" => id,
          "result" => result
        }
      end

      def invalid_request_response(id)
        error_response(id, -32_600, "Invalid Request")
      end

      def error_response(id, code, message)
        {
          "jsonrpc" => "2.0",
          "id" => id,
          "error" => {
            "code" => code,
            "message" => message
          }
        }
      end

      # Raised when a JSON-RPC request method is not supported.
      class MethodNotFound < StandardError; end

      # Raised when request parameters are malformed for the requested method.
      class InvalidParams < StandardError; end
    end
  end
end
