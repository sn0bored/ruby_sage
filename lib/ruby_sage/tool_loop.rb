# frozen_string_literal: true

require "json"

module RubySage
  # Runs the provider/tool-call loop for one chat turn. Delegates each provider
  # round to {RubySage.provider}; when the response contains tool_use blocks,
  # dispatches them through {RubySage::Tools::Registry} and re-issues the
  # provider call with tool_result messages until the model stops requesting
  # tools or +max_iterations+ is reached.
  #
  # The loop is provider-shape-aware (Anthropic-style content blocks). Other
  # providers receive the standard non-tool +chat+ contract.
  class ToolLoop
    # @param registry [RubySage::Tools::Registry]
    # @param provider [RubySage::Providers::Base]
    # @param max_iterations [Integer]
    # @return [RubySage::ToolLoop]
    def initialize(registry:, provider: RubySage.provider,
                   max_iterations: RubySage.configuration.tool_loop_max_iterations)
      @registry = registry
      @provider = provider
      @max_iterations = max_iterations
    end

    # Drives one chat turn to completion.
    #
    # @param system_prompt [String]
    # @param cached_context [String, nil]
    # @param messages [Array<Hash>] working messages array; the loop appends
    #   to a copy, never mutating the caller's array.
    # @return [Hash] +{ answer:, tool_calls: [...], usage: ..., iterations: N }+.
    def run(system_prompt:, cached_context:, messages:)
      working = messages.dup
      executed_calls = []
      response = nil
      iterations = 0

      @max_iterations.times do
        iterations += 1
        response = call_provider(system_prompt, cached_context, working)
        break if no_tool_calls?(response)

        record_calls(executed_calls, response[:tool_calls])
        append_assistant_and_tool_results(working, response)
      end

      finished(response, executed_calls, iterations)
    end

    private

    def call_provider(system_prompt, cached_context, messages)
      tools = @registry.empty? ? nil : @registry.to_anthropic
      @provider.chat(
        system_prompt: system_prompt,
        cached_context: cached_context,
        messages: messages,
        tools: tools
      )
    end

    def no_tool_calls?(response)
      Array(response[:tool_calls]).empty?
    end

    def record_calls(history, calls)
      Array(calls).each do |call|
        history << { id: call[:id], name: call[:name], input: call[:input] }
      end
    end

    def append_assistant_and_tool_results(messages, response)
      messages << { role: "assistant", content: response[:raw_content] }

      tool_results = Array(response[:tool_calls]).map do |call|
        result = @registry.dispatch(name: call[:name], input: call[:input])
        {
          type: "tool_result",
          tool_use_id: call[:id],
          content: JSON.generate(result)
        }
      end
      messages << { role: "user", content: tool_results }
    end

    def finished(response, executed_calls, iterations)
      {
        answer: response.is_a?(Hash) ? response[:answer].to_s : "",
        tool_calls: executed_calls,
        usage: response.is_a?(Hash) ? response[:usage] : {},
        iterations: iterations
      }
    end
  end
end
