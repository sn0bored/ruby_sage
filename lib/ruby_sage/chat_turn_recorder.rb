# frozen_string_literal: true

module RubySage
  # Persists one +ChatTurn+ row from a chat-controller turn. Extracted from the
  # controller so the controller stays focused on request/response and the
  # recording logic is independently testable.
  class ChatTurnRecorder
    # @param controller [ActionController::Base] the controller handling the
    #   request — used by +config.identify_asker+.
    # @return [RubySage::ChatTurnRecorder]
    def initialize(controller:)
      @controller = controller
    end

    # Writes a turn row. Returns the persisted record on success, nil on
    # disabled-by-config or any rescue.
    #
    # @param question [String]
    # @param retrieval [Hash, nil] the retriever's result hash.
    # @param result [Hash, nil] the chat run's result hash, or nil on failure.
    # @param status [String] "completed" or "failed".
    # @param error_message [String, nil]
    # @return [RubySage::ChatTurn, nil]
    def call(question:, retrieval:, result:, status:, error_message: nil)
      return nil unless RubySage.configuration.persist_chat_turns

      ChatTurn.create!(attributes_for(question, retrieval, result, status, error_message))
    rescue StandardError => e
      Rails.logger.warn("[RubySage::ChatTurn] failed to persist: #{e.message}")
      nil
    end

    private

    attr_reader :controller

    def attributes_for(question, retrieval, result, status, error_message)
      usage = result.is_a?(Hash) ? result[:usage] : nil
      base_attributes(question, retrieval, status, error_message)
        .merge(answer_attributes(result))
        .merge(usage_attributes(usage))
    end

    def base_attributes(question, retrieval, status, error_message)
      {
        scan_id: retrieval&.dig(:scan_id),
        mode: RubySage.configuration.mode.to_s,
        model: RubySage.configuration.model,
        question: question.to_s,
        citations: retrieval ? Array(retrieval[:citations]) : [],
        status: status,
        error_message: error_message,
        asker: identify_asker
      }
    end

    def answer_attributes(result)
      return { answer: nil, tool_calls: [], iterations: nil } unless result.is_a?(Hash)

      {
        answer: result[:answer],
        tool_calls: Array(result[:tool_calls]),
        iterations: result[:iterations]
      }
    end

    def usage_attributes(usage)
      return {} unless usage.is_a?(Hash)

      {
        input_tokens: usage[:input_tokens],
        output_tokens: usage[:output_tokens],
        cache_creation_tokens: usage[:cache_creation_input_tokens],
        cache_read_tokens: usage[:cache_read_input_tokens]
      }
    end

    def identify_asker
      callable = RubySage.configuration.identify_asker
      return nil if callable.nil?

      result = callable.call(controller)
      result.is_a?(ActiveRecord::Base) ? result : nil
    rescue StandardError
      nil
    end
  end
end
