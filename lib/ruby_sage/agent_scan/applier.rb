# frozen_string_literal: true

require "json"
require "pathname"

module RubySage
  module AgentScan
    # Reads a planner-built manifest plus an agent-produced summaries file and
    # creates a +Scan+ + +Artifacts+ in a single transaction. Designed so the
    # same flow works locally (agent on dev box) and in production (manifest +
    # summaries shipped from CI).
    class Applier
      # Raised when the manifest or summaries file is missing or malformed.
      class InvalidManifest < StandardError; end

      # Initializes an applier.
      #
      # @param manifest_path [String, Pathname]
      # @param summaries_path [String, Pathname]
      # @return [RubySage::AgentScan::Applier]
      def initialize(manifest_path:, summaries_path:)
        @manifest_path = Pathname(manifest_path).expand_path
        @summaries_path = Pathname(summaries_path).expand_path
      end

      # Persists a new completed scan from the manifest + summaries.
      #
      # @return [RubySage::Scan]
      def run
        manifest = load_manifest
        agent_payload = load_summaries

        scan = nil
        Scan.transaction do
          scan = create_scan(manifest)
          create_artifacts(scan, manifest, agent_payload)
        end
        prune_old_scans
        scan
      end

      private

      attr_reader :manifest_path, :summaries_path

      def load_manifest
        raise InvalidManifest, "Manifest not found at #{manifest_path}" unless manifest_path.file?

        manifest = JSON.parse(manifest_path.read)
        raise InvalidManifest, "Unsupported manifest schema_version: #{manifest['schema_version']}" \
          unless manifest["schema_version"] == SCHEMA_VERSION
        raise InvalidManifest, "Manifest is missing 'files' array" unless manifest["files"].is_a?(Array)

        manifest
      rescue JSON::ParserError => e
        raise InvalidManifest, "Manifest is not valid JSON: #{e.message}"
      end

      def load_summaries
        return { "summaries" => {}, "audience_overrides" => {} } unless summaries_path.file?

        payload = JSON.parse(summaries_path.read)
        raise InvalidManifest, "Unsupported summaries schema_version: #{payload['schema_version']}" \
          unless payload["schema_version"] == SCHEMA_VERSION

        {
          "summaries" => Hash(payload["summaries"]),
          "audience_overrides" => Hash(payload["audience_overrides"])
        }
      rescue JSON::ParserError => e
        raise InvalidManifest, "Summaries file is not valid JSON: #{e.message}"
      end

      def create_scan(manifest)
        Scan.create!(
          status: "completed",
          started_at: Time.current,
          finished_at: Time.current,
          git_sha: manifest["git_sha"],
          ruby_version: manifest["ruby_version"],
          rails_version: manifest["rails_version"],
          file_count: manifest["files"].size
        )
      end

      def create_artifacts(scan, manifest, agent_payload)
        summaries = agent_payload["summaries"]
        overrides = agent_payload["audience_overrides"]

        manifest["files"].each do |entry|
          Artifact.create!(
            scan: scan,
            path: entry["path"],
            kind: entry["kind"],
            digest: entry["digest"],
            public_symbols: Array(entry["public_symbols"]),
            audiences: resolve_audiences(entry, overrides),
            route_mappings: entry["route_mappings"],
            summary: resolve_summary(entry, summaries)
          )
        end
      end

      def resolve_audiences(entry, overrides)
        override = overrides[entry["path"]]
        return Array(override).map(&:to_s) unless override.nil?

        Array(entry["audiences"]).map(&:to_s)
      end

      def resolve_summary(entry, summaries)
        agent_summary = summaries[entry["path"]]
        return agent_summary if agent_summary.is_a?(String) && !agent_summary.strip.empty?

        entry["previous_summary"]
      end

      def prune_old_scans
        retention = RubySage.configuration.scan_retention.to_i
        return unless retention.positive?

        stale_ids = Scan.order(finished_at: :desc, created_at: :desc).offset(retention).pluck(:id)
        Scan.where(id: stale_ids).order(:created_at).each(&:destroy!)
      end
    end
  end
end
