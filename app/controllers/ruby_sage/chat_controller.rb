# frozen_string_literal: true

module RubySage
  # Handles a chat turn — single message or multi-turn — by retrieving relevant
  # artifacts, calling the configured provider, and returning an answer with
  # citations. Accepts either a +messages+ array (multi-turn) or a legacy single
  # +message+ string for backwards compatibility. The system prompt adapts to the
  # configured +mode+ (:developer, :admin, or :user) via {RubySage::Prompts}.
  class ChatController < ApplicationController
    # Answers a user question against retrieved codebase artifacts.
    # Accepts multi-turn +messages+ array or a single +message+ string.
    #
    # @return [void]
    def create
      messages = permitted_messages
      page_context = permitted_page_context
      query = last_user_message(messages)
      retrieval = RubySage::Retriever.new.call(query: query, page_context: page_context)
      tool_registry = RubySage::Tools::Registry.for(mode: RubySage.configuration.mode, controller: self)
      result = run_chat(messages, page_context, retrieval, tool_registry)

      render json: response_payload(result, retrieval, tool_registry)
    rescue Providers::ProviderError => e
      render json: { error: "provider_error", detail: e.message }, status: :bad_gateway
    rescue ActionController::ParameterMissing => e
      render json: { error: "parameter_missing", detail: e.message }, status: :bad_request
    end

    private

    # Extracts the conversation as a normalized messages array. Accepts either
    # a +messages+ array param (multi-turn) or falls back to a single +message+
    # string (legacy single-turn format).
    #
    # @return [Array<Hash>] messages with symbolized :role and :content keys.
    # @raise [ActionController::ParameterMissing] when neither param is present.
    def permitted_messages
      if params[:messages].present?
        params.require(:messages).map { |m| m.permit(:role, :content).to_h.symbolize_keys }
      else
        [{ role: "user", content: params.require(:message) }]
      end
    end

    # Extracts the most recent user message for use as the retrieval query.
    #
    # @param messages [Array<Hash>]
    # @return [String]
    def last_user_message(messages)
      messages.reverse.find { |m| m[:role].to_s == "user" }&.dig(:content).to_s
    end

    def permitted_page_context
      page_context = params[:page_context]
      return nil if page_context.nil?

      page_context.permit(:url, :title).to_h.symbolize_keys
    end

    def build_artifact_context(artifacts)
      return "" if artifacts.empty?

      blocks = artifacts.map do |artifact|
        "## #{artifact.path} (#{artifact.kind})\n\n" \
          "Public symbols: #{Array(artifact.public_symbols).join(', ')}\n\n" \
          "Summary:\n#{artifact.summary || '(no summary available)'}\n"
      end

      "Codebase context:\n\n#{blocks.join("\n---\n\n")}"
    end

    # Prepends page context to the first user message so the provider sees it
    # without polluting the conversation history the caller maintains.
    #
    # @param messages [Array<Hash>]
    # @param page_context [Hash, nil]
    # @return [Array<Hash>]
    def messages_with_context(messages, page_context)
      return messages unless page_context&.dig(:url)

      first_user_idx = messages.index { |m| m[:role].to_s == "user" }
      return messages if first_user_idx.nil?

      annotated = messages.dup
      first = annotated[first_user_idx].dup
      first[:content] = "#{first[:content]}\n\n[Currently viewing: #{page_context[:url]}]"
      annotated[first_user_idx] = first
      annotated
    end

    def run_chat(messages, page_context, retrieval, tool_registry)
      system_prompt = RubySage::Prompts.for_mode(
        RubySage.configuration.mode,
        with_database_tools: !tool_registry.empty?,
        query_scope_hint: query_scope_hint
      )
      cached_context = build_artifact_context(retrieval[:artifacts])
      annotated_messages = messages_with_context(messages, page_context)

      if tool_registry.empty?
        single_shot(system_prompt, cached_context, annotated_messages)
      else
        RubySage::ToolLoop.new(registry: tool_registry).run(
          system_prompt: system_prompt,
          cached_context: cached_context,
          messages: annotated_messages
        )
      end
    end

    def single_shot(system_prompt, cached_context, messages)
      response = RubySage.provider.chat(
        system_prompt: system_prompt,
        cached_context: cached_context,
        messages: messages
      )
      { answer: response[:answer], usage: response[:usage], tool_calls: [], iterations: 1 }
    end

    def query_scope_hint
      callable = RubySage.configuration.query_scope
      return nil if callable.nil?

      callable.call(self)
    end

    def response_payload(result, retrieval, tool_registry)
      payload = {
        answer: result[:answer],
        citations: retrieval[:citations],
        scan_id: retrieval[:scan_id],
        usage: result[:usage]
      }
      payload[:tool_calls] = result[:tool_calls] if result[:tool_calls]&.any?
      payload[:iterations] = result[:iterations] if result[:iterations] && !tool_registry.empty?
      payload
    end
  end
end
