# frozen_string_literal: true

module RubySage
  module Admin
    # Audit + usage view for the chat widget. Lists recent +ChatTurn+ rows with
    # filters for mode, status, and tool usage. Detail view shows the full
    # question/answer, tool calls (including the SQL the model ran in
    # +:admin+ mode), citations, and token usage.
    class ChatTurnsController < ApplicationController
      RECENT_LIMIT = 100
      private_constant :RECENT_LIMIT

      # Lists recent chat turns, optionally filtered.
      #
      # @return [void]
      def index
        @turns = filtered_turns.recent.limit(RECENT_LIMIT)
        @stats = aggregate_stats
        @filters = current_filters
      end

      # Shows one chat turn in detail (question, answer, tool calls, citations).
      #
      # @return [void]
      def show
        @turn = RubySage::ChatTurn.find(params[:id])
      end

      private

      def filtered_turns
        scope = RubySage::ChatTurn.all
        scope = scope.for_mode(params[:mode]) if params[:mode].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.with_tool_calls if params[:tools] == "1"
        scope
      end

      def aggregate_stats
        scope = RubySage::ChatTurn.where("created_at > ?", 30.days.ago)
        {
          total: scope.count,
          failed: scope.failed.count,
          with_tool_calls: scope.with_tool_calls.count,
          input_tokens: scope.sum(:input_tokens),
          output_tokens: scope.sum(:output_tokens),
          cache_read_tokens: scope.sum(:cache_read_tokens)
        }
      end

      def current_filters
        { mode: params[:mode], status: params[:status], tools: params[:tools] }
      end
    end
  end
end
