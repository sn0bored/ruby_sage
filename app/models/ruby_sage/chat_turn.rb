# frozen_string_literal: true

module RubySage
  # One row per chat-widget exchange. Captures the question, the model's final
  # answer, every tool call the loop made, citations, token usage, mode, and
  # the asker (when the host opts in via +config.identify_asker+).
  #
  # Powers the admin audit dashboard and the future SaaS usage metering.
  class ChatTurn < ApplicationRecord
    self.table_name = "ruby_sage_chat_turns"

    belongs_to :scan, class_name: "RubySage::Scan", optional: true
    belongs_to :asker, polymorphic: true, optional: true

    validates :status, inclusion: { in: %w[completed failed] }
    validates :mode, presence: true
    validates :question, presence: true

    if method(:serialize).parameters.any? { |type, name| type == :key && name == :coder }
      serialize :tool_calls, coder: JSON
      serialize :citations, coder: JSON
    else
      serialize :tool_calls, JSON
      serialize :citations, JSON
    end

    scope :recent, -> { order(created_at: :desc) }
    scope :failed, -> { where(status: "failed") }
    scope :with_tool_calls, -> { where.not(tool_calls: [nil, "[]"]) }
    scope :for_mode, ->(mode) { where(mode: mode.to_s) }

    # Total tokens billed (input + output, ignoring cache discounts).
    #
    # @return [Integer]
    def total_tokens
      input_tokens.to_i + output_tokens.to_i
    end

    # True when at least one tool was invoked during this turn.
    #
    # @return [Boolean]
    def used_tools?
      Array(tool_calls).any?
    end

    # USD cost of this turn, calculated from token usage and the recorded
    # model name. Returns nil when the model is unknown to the calculator.
    #
    # @return [Float, nil]
    def cost_usd
      RubySage::CostCalculator.call(
        model: model,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        cache_read_tokens: cache_read_tokens,
        cache_creation_tokens: cache_creation_tokens
      )
    end
  end
end
