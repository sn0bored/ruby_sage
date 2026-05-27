# frozen_string_literal: true

require "ruby_sage/artifacts/disk_store"

module RubySage
  # Rebuilds the widget's database (Scan + Artifact rows) from the on-disk
  # `.ruby_sage/` layout. This is the one-way street that makes the disk
  # layout the source of truth: scans write disk, the Indexer fans out to DB.
  #
  # @example Reindex from CLI after editing artifacts on disk
  #   RubySage::Indexer.new(host_root: Rails.root).run
  class Indexer
    # @param host_root [String, Pathname]
    # @param disk_store [RubySage::Artifacts::DiskStore]
    def initialize(host_root:, disk_store: nil)
      @host_root = host_root
      @disk_store = disk_store || Artifacts::DiskStore.new(host_root: host_root)
    end

    # Reads `.ruby_sage/manifest.json` + every artifact on disk and upserts a
    # single completed Scan with matching Artifact rows.
    #
    # @return [RubySage::Scan]
    # @raise [Indexer::MissingManifest] when `.ruby_sage/manifest.json` is absent.
    def run
      manifest = disk_store.read_manifest
      raise MissingManifest, "No manifest at #{disk_store.manifest_path}" if manifest.nil?

      scan = create_scan(manifest)
      create_artifacts(scan)
      scan
    end

    # Raised when the on-disk layout has no manifest to index.
    class MissingManifest < StandardError; end

    private

    attr_reader :host_root, :disk_store

    def create_scan(manifest)
      Scan.create!(
        status: "completed",
        git_sha: manifest[:git_sha],
        ruby_version: manifest[:ruby_version],
        rails_version: manifest[:rails_version],
        file_count: manifest[:file_count].to_i,
        started_at: parse_time(manifest[:started_at]),
        finished_at: parse_time(manifest[:finished_at]) || Time.current
      )
    end

    def create_artifacts(scan)
      disk_store.each_artifact do |payload|
        Artifact.create!(
          scan: scan,
          path: payload[:path],
          kind: payload[:kind],
          digest: payload[:digest],
          summary: payload[:summary],
          signature: payload[:signature],
          public_symbols: Array(payload[:public_symbols]),
          route_mappings: payload[:route_mappings],
          audiences: Array(payload[:audiences])
        )
      end
    end

    def parse_time(value)
      return nil if value.nil?
      return value if value.is_a?(Time)

      Time.zone&.parse(value.to_s) || Time.parse(value.to_s).utc
    rescue ArgumentError
      nil
    end
  end
end
