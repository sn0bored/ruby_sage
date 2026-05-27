# frozen_string_literal: true

module RubySage
  class Scanner
    # Writes a completed Scan's artifacts to the `.ruby_sage/` disk layout.
    #
    # The Scanner persists everything to ActiveRecord first; this class fans
    # the result out to disk so the MCP server (and any other process that
    # doesn't boot Rails) can read it.
    class DiskMirror
      # @param scan [RubySage::Scan] a completed Scan with its Artifacts loaded.
      # @param disk_store [RubySage::Artifacts::DiskStore]
      # @param scanner_config [RubySage::Configuration]
      def initialize(scan:, disk_store:, scanner_config:)
        @scan = scan
        @disk_store = disk_store
        @scanner_config = scanner_config
      end

      # @return [void]
      def run
        write_each_artifact
        prune_stale_artifacts
        write_manifest
      end

      private

      attr_reader :scan, :disk_store, :scanner_config

      def write_each_artifact
        scan.artifacts.find_each do |artifact|
          disk_store.write_artifact(path: artifact.path, attributes: artifact_attributes(artifact))
        end
      end

      def prune_stale_artifacts
        disk_store.prune_artifacts_outside(scan.artifacts.pluck(:path))
      end

      def write_manifest
        disk_store.write_manifest(attributes: manifest_attributes)
      end

      def artifact_attributes(artifact)
        {
          kind: artifact.kind,
          digest: artifact.digest,
          summary: artifact.summary,
          public_symbols: Array(artifact.public_symbols),
          route_mappings: artifact.route_mappings,
          audiences: Array(artifact.audiences)
        }
      end

      def manifest_attributes
        {
          git_sha: scan.git_sha,
          ruby_version: scan.ruby_version,
          rails_version: scan.rails_version,
          started_at: scan.started_at,
          finished_at: Time.current,
          file_count: scan.artifacts.count,
          scanner: {
            "include" => Array(scanner_config.scanner_include),
            "exclude" => Array(scanner_config.scanner_exclude)
          }
        }
      end
    end
  end
end
