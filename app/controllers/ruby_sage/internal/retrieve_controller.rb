# frozen_string_literal: true

module RubySage
  module Internal
    class RetrieveController < RubySage::ApplicationController
      skip_before_action :verify_authenticity_token

      # Returns retrieved code context for a natural-language query.
      #
      # @return [void]
      def create
        result = RubySage::Retriever.new.call(
          query: params.require(:query),
          page_context: permitted_page_context
        )

        render json: result
      end

      private

      def permitted_page_context
        page_context = params[:page_context]
        return nil if page_context.nil?

        page_context.permit(:url, :title).to_h.symbolize_keys
      end
    end
  end
end
