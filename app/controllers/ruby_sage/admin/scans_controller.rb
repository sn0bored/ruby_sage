# frozen_string_literal: true

module RubySage
  module Admin
    # Displays scan history and artifact statistics, and exposes a manual rescan
    # trigger. Inherits RubySage auth from the engine's ApplicationController.
    class ScansController < ApplicationController
      # Lists completed and in-progress scans with artifact breakdowns.
      #
      # @return [void]
      def index
        @scans = RubySage::Scan.order(created_at: :desc).limit(20)
        @latest = @scans.find { |s| s.status == "completed" }
        @artifact_counts = artifact_counts_for(@latest)
        @running = @scans.any? { |s| s.status == "running" }
      end

      # Enqueues a background rescan of the host application.
      #
      # @return [void]
      def create
        RubySage::ScanJob.perform_later
        redirect_to ruby_sage.admin_scans_path,
                    notice: "Scan queued. Refresh in a moment to see results."
      rescue NameError
        # ScanJob not wired yet; fall back to synchronous scan.
        RubySage::Scanner.new(host_root: Rails.root).run
        redirect_to ruby_sage.admin_scans_path, notice: "Scan complete."
      end

      private

      # @param scan [RubySage::Scan, nil]
      # @return [Hash{String => Integer}]
      def artifact_counts_for(scan)
        return {} if scan.nil?

        scan.artifacts.group_by(&:kind).transform_values(&:count)
      end
    end
  end
end
