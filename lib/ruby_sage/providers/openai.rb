# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module RubySage
  module Providers
    # Calls OpenAI's Chat Completions API.
    #
    # @example
    #   RubySage.configure do |config|
    #     config.provider = :openai
    #     config.api_key = ENV["OPENAI_API_KEY"]
    #     config.model = "gpt-4.1-mini"
    #   end
    #   RubySage.provider.chat(
    #     system_prompt: "You answer questions about a Rails codebase.",
    #     cached_context: "<artifact summaries here>",
    #     messages: [{ role: "user", content: "what does PostsController do?" }]
    #   )
    class OpenAI < Base
      API_URL = "https://api.openai.com/v1/chat/completions"

      # Sends a chat request to OpenAI.
      #
      # @param system_prompt [String]
      # @param cached_context [String, nil] artifact context block appended to the system message.
      # @param messages [Array<Hash>] each item contains :role and :content.
      # @yield [String] each streamed chunk. V1 ignores the block; v1.5 will yield chunks.
      # @return [Hash] response with :answer, :citations, and :usage keys.
      # @raise [ArgumentError] when no API key is configured.
      # @raise [RubySage::Providers::ProviderError] when OpenAI returns an error.
      def chat(system_prompt:, cached_context:, messages:, &block)
        ignore_streaming_block(block)
        raise ArgumentError, "api_key not configured" if @config.api_key.nil?

        response = post_json(build_body(system_prompt, cached_context, messages))

        {
          answer: extract_answer(response),
          citations: [],
          usage: extract_usage(response)
        }
      end

      private

      def ignore_streaming_block(_block); end

      def build_body(system_prompt, cached_context, messages)
        {
          model: @config.model,
          max_tokens: 1024,
          messages: build_messages(system_prompt, cached_context, messages)
        }
      end

      def build_messages(system_prompt, cached_context, messages)
        [{ role: "system", content: system_content(system_prompt, cached_context) }] + messages
      end

      def system_content(system_prompt, cached_context)
        return system_prompt if cached_context.to_s.empty?

        "#{system_prompt}\n\n#{cached_context}"
      end

      def post_json(body)
        uri = URI(API_URL)
        request = build_request(uri, body)

        parse_response(perform_request(uri, request))
      end

      def build_request(uri, body)
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer #{@config.api_key}"
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
          raise ProviderError, "OpenAI returned #{response.code}: #{response.body}"
        end

        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise ProviderError, "OpenAI returned invalid JSON: #{e.message}"
      end

      def extract_answer(payload)
        choices = payload["choices"] || []
        first_choice = choices.first || {}
        message = first_choice["message"] || {}

        message["content"].to_s
      end

      def extract_usage(payload)
        usage = payload["usage"] || {}
        {
          input_tokens: usage["prompt_tokens"],
          output_tokens: usage["completion_tokens"],
          total_tokens: usage["total_tokens"]
        }
      end
    end
  end
end
