# frozen_string_literal: true

module RubySage
  module Admin
    # Browses the artifact index from the latest completed scan. Useful for new
    # developers who want to read through what got indexed without asking questions.
    class ArtifactsController < ApplicationController
      ARTIFACTS_PER_PAGE = 50

      # Lists artifacts filtered by kind, with pagination.
      #
      # @return [void]
      def index
        @scan = Scan.latest_completed.first
        @kinds = all_kinds
        @current_kind = params[:kind].presence
        @artifacts = scoped_artifacts
        @page = [params[:page].to_i, 1].max
        @artifacts = @artifacts.offset((@page - 1) * ARTIFACTS_PER_PAGE).limit(ARTIFACTS_PER_PAGE)
        @total = scoped_artifacts.count
        @total_pages = [(@total.to_f / ARTIFACTS_PER_PAGE).ceil, 1].max
      end

      private

      # @return [Array<String>] unique kinds present in the latest scan.
      def all_kinds
        return [] if @scan.nil?

        @scan.artifacts.pluck(:kind).compact.uniq.sort
      end

      # @return [ActiveRecord::Relation]
      def scoped_artifacts
        return Artifact.none if @scan.nil?

        scope = @scan.artifacts.order(:kind, :path)
        @current_kind ? scope.where(kind: @current_kind) : scope
      end
    end
  end
end
