# frozen_string_literal: true

module RubySage
  # Handles a chat turn — single message or multi-turn — by retrieving relevant
  # artifacts, calling the configured provider, and returning an answer with
  # citations. Accepts either a +messages+ array (multi-turn) or a legacy single
  # +message+ string for backwards compatibility.
  class ChatController < ApplicationController
    SYSTEM_PROMPT = <<~PROMPT
      You are answering questions about a Ruby on Rails application's source code.
      Answer using only the artifacts in the provided context. If the context does
      not contain enough information to answer, say so plainly. Always be specific:
      reference class and method names, file paths, and route mappings when relevant.
      Keep answers tight - no preamble, no apology, no fluff.
    PROMPT
    private_constant :SYSTEM_PROMPT

    # Answers a user question against retrieved codebase artifacts.
    # Accepts multi-turn +messages+ array or a single +message+ string.
    #
    # @return [void]
    def create
      messages = permitted_messages
      page_context = permitted_page_context
      query = last_user_message(messages)
      retrieval = RubySage::Retriever.new.call(query: query, page_context: page_context)
      provider_response = provider_response_for(messages, page_context, retrieval)

      render json: response_payload(provider_response, retrieval)
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

    def provider_response_for(messages, page_context, retrieval)
      RubySage.provider.chat(
        system_prompt: SYSTEM_PROMPT,
        cached_context: build_artifact_context(retrieval[:artifacts]),
        messages: messages_with_context(messages, page_context)
      )
    end

    def response_payload(provider_response, retrieval)
      {
        answer: provider_response[:answer],
        citations: retrieval[:citations],
        scan_id: retrieval[:scan_id],
        usage: provider_response[:usage]
      }
    end
  end
end
