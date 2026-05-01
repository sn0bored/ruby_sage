# frozen_string_literal: true

module RubySage
  # Handles a single chat turn by retrieving relevant artifacts, calling the
  # configured provider, and returning an answer with citations.
  class ChatController < ApplicationController
    skip_before_action :verify_authenticity_token

    SYSTEM_PROMPT = <<~PROMPT
      You are answering questions about a Ruby on Rails application's source code.
      Answer using only the artifacts in the provided context. If the context does
      not contain enough information to answer, say so plainly. Always be specific:
      reference class and method names, file paths, and route mappings when relevant.
      Keep answers tight - no preamble, no apology, no fluff.
    PROMPT

    # Answers a user question against retrieved codebase artifacts.
    #
    # @return [void]
    def create
      message = params.require(:message)
      page_context = permitted_page_context
      retrieval = RubySage::Retriever.new.call(query: message, page_context: page_context)
      provider_response = provider_response_for(message, page_context, retrieval)

      render json: response_payload(provider_response, retrieval)
    rescue Providers::ProviderError => e
      render json: { error: "provider_error", detail: e.message }, status: :bad_gateway
    rescue ActionController::ParameterMissing => e
      render json: { error: "parameter_missing", detail: e.message }, status: :bad_request
    end

    private

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

    def build_messages(user_message, page_context)
      content = user_message
      content += "\n\n[Currently viewing: #{page_context[:url]}]" if page_context&.dig(:url)

      [{ role: "user", content: content }]
    end

    def provider_response_for(message, page_context, retrieval)
      RubySage.provider.chat(
        system_prompt: SYSTEM_PROMPT,
        cached_context: build_artifact_context(retrieval[:artifacts]),
        messages: build_messages(message, page_context)
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
