# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module RubySage
  module Providers
    # Calls Anthropic's Messages API. Uses prompt caching on the artifact
    # context block so repeat calls within a 5-minute window cost less.
    #
    # @example
    #   RubySage.configure do |config|
    #     config.provider = :anthropic
    #     config.api_key = ENV["ANTHROPIC_API_KEY"]
    #     config.model = "claude-sonnet-4-6"
    #   end
    #   RubySage.provider.chat(
    #     system_prompt: "You answer questions about a Rails codebase.",
    #     cached_context: "<artifact summaries here>",
    #     messages: [{ role: "user", content: "what does PostsController do?" }]
    #   )
    class Anthropic < Base
      API_URL = "https://api.anthropic.com/v1/messages"
      API_VERSION = "2023-06-01"

      # Sends a chat request to Anthropic.
      #
      # @param system_prompt [String]
      # @param cached_context [String, nil] artifact context block; receives prompt-cache marker.
      # @param messages [Array<Hash>] each item contains :role and :content.
      # @param tools [Array<Hash>, nil] Anthropic-shaped tool definitions.
      # @yield [String] each streamed chunk. V1 ignores the block; v1.5 will yield chunks.
      # @return [Hash] response with +:answer+, +:citations+, +:usage+, plus
      #   +:tool_calls+ (extracted +tool_use+ blocks), +:stop_reason+, and
      #   +:raw_content+ (raw content blocks for echoing back into the next
      #   request when looping on tool calls).
      # @raise [ArgumentError] when no API key is configured.
      # @raise [RubySage::Providers::ProviderError] when Anthropic returns an error.
      def chat(system_prompt:, cached_context:, messages:, tools: nil, &block)
        ignore_streaming_block(block)
        raise ArgumentError, "api_key not configured" if @config.api_key.nil?

        response = post_json(build_body(system_prompt, cached_context, messages, tools))
        content_blocks = response["content"] || []

        {
          answer: extract_answer(content_blocks),
          citations: [],
          usage: extract_usage(response),
          tool_calls: extract_tool_calls(content_blocks),
          stop_reason: response["stop_reason"],
          raw_content: content_blocks
        }
      end

      private

      def ignore_streaming_block(_block); end

      def build_body(system_prompt, cached_context, messages, tools)
        body = {
          model: @config.model,
          max_tokens: 1024,
          system: build_system_blocks(system_prompt, cached_context),
          messages: messages
        }
        body[:tools] = tools if tools.present?
        body
      end

      def build_system_blocks(system_prompt, cached_context)
        system_blocks = [{ type: "text", text: system_prompt }]
        return system_blocks if cached_context.to_s.empty?

        system_blocks << {
          type: "text",
          text: cached_context,
          cache_control: { type: "ephemeral" }
        }
      end

      def post_json(body)
        uri = URI(API_URL)
        request = build_request(uri, body)

        parse_response(perform_request(uri, request))
      end

      def build_request(uri, body)
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["x-api-key"] = @config.api_key
        request["anthropic-version"] = API_VERSION
        request.body = body.to_json
        request
      end

      def perform_request(uri, request)
        Net::HTTP.start(
          uri.hostname,
          uri.port,
          use_ssl: true,
          read_timeout: @config.request_timeout,
          open_timeout: @config.request_timeout
        ) { |http| http.request(request) }
      end

      def parse_response(response)
        unless response.is_a?(Net::HTTPSuccess)
          raise ProviderError, "Anthropic returned #{response.code}: #{response.body}"
        end

        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise ProviderError, "Anthropic returned invalid JSON: #{e.message}"
      end

      def extract_answer(content_blocks)
        text_blocks = content_blocks.select { |content_block| content_block["type"] == "text" }
        text_blocks.map { |content_block| content_block.fetch("text", "") }.join
      end

      def extract_tool_calls(content_blocks)
        content_blocks.select { |block| block["type"] == "tool_use" }.map do |block|
          { id: block["id"], name: block["name"], input: block["input"] || {} }
        end
      end

      def extract_usage(payload)
        usage = payload["usage"] || {}
        {
          input_tokens: usage["input_tokens"],
          output_tokens: usage["output_tokens"],
          cache_creation_input_tokens: usage["cache_creation_input_tokens"],
          cache_read_input_tokens: usage["cache_read_input_tokens"]
        }
      end
    end
  end
end
