# frozen_string_literal: true

require "fileutils"
require "pathname"
require "ruby_sage/artifacts/disk_store"
require "ruby_sage/extractors/routes_loader"
require "ruby_sage/indexer"
require "ruby_sage/secret_redactor"
require "ruby_sage/scanner/artifact_builder"
require "ruby_sage/scanner/walker"
require "ruby_sage/summarizer"

module RubySage
  # Walks the host app filesystem, writes disk artifacts, and indexes them.
  #
  # @example
  #   scan = RubySage::Scanner.new(host_root: Rails.root).run
  #   scan.artifacts.count
  class Scanner
    # Initializes a scanner for a host Rails root.
    #
    # @param host_root [String, Pathname] root directory of the host app.
    # @param config [RubySage::Configuration]
    # @return [RubySage::Scanner]
    def initialize(host_root:, config: RubySage.configuration, disk_store: nil)
      @host_root = Pathname(host_root).expand_path
      @config = config
      @disk_store = disk_store || Artifacts::DiskStore.new(host_root: @host_root)
    end

    # Runs a locked filesystem scan and returns the indexed scan.
    #
    # @return [RubySage::Scan]
    def run
      with_lock { scan_to_disk_and_index }
    end

    private

    attr_reader :host_root, :config, :disk_store

    def scan_to_disk_and_index
      previous_artifacts = latest_completed_artifacts_by_path
      started_at = Time.current
      disk_store.ensure_layout
      artifact_inputs = build_artifact_inputs
      write_artifacts(artifact_inputs)
      summarize_artifacts(artifact_inputs, previous_artifacts)
      disk_store.prune_artifacts_outside(artifact_paths(artifact_inputs))
      write_manifest(started_at: started_at, file_count: artifact_inputs.size)
      Extractors::RoutesLoader.new(host_root: host_root).run
      scan = Indexer.new(host_root: host_root, disk_store: disk_store).run
      prune_old_scans
      scan
    end

    def build_artifact_inputs
      artifact_builder = ArtifactBuilder.new(host_root: host_root)
      Walker.new(host_root: host_root, config: config).paths.map do |path|
        artifact_builder.build(path: path)
      end
    end

    def write_artifacts(artifact_inputs)
      artifact_inputs.each do |input|
        disk_store.write_artifact(path: input[:path], attributes: input[:attributes])
      end
    end

    def artifact_paths(artifact_inputs)
      artifact_inputs.each_with_object([]) do |input, paths|
        paths << input[:path]
      end
    end

    def summarize_artifacts(artifact_inputs, previous_artifacts)
      summarizer = Summarizer.new(config: config)
      artifact_inputs.each do |input|
        summary = summary_for(input, previous_artifacts, summarizer)
        next if summary.nil?

        input[:attributes][:summary] = summary
        disk_store.write_artifact(path: input[:path], attributes: input[:attributes])
      end
    end

    def summary_for(input, previous_artifacts, summarizer)
      previous = previous_artifacts[input[:path]]
      return previous.summary if previous&.digest == input[:attributes][:digest]

      summarizer.summarize(contents: input[:contents], path: input[:path])
    end

    def write_manifest(started_at:, file_count:)
      disk_store.write_manifest(
        attributes: {
          git_sha: detect_git_sha,
          ruby_version: RUBY_VERSION,
          rails_version: Rails::VERSION::STRING,
          started_at: started_at,
          finished_at: Time.current,
          file_count: file_count,
          scanner: { "include" => Array(config.scanner_include), "exclude" => Array(config.scanner_exclude) }
        }
      )
    end

    def latest_completed_artifacts_by_path
      latest_scan = Scan.latest_completed.first
      return {} if latest_scan.nil?

      latest_scan.artifacts.index_by(&:path)
    end

    def prune_old_scans
      retention = config.scan_retention.to_i
      return unless retention.positive?

      stale_ids = Scan.order(finished_at: :desc, created_at: :desc).offset(retention).pluck(:id)
      Scan.where(id: stale_ids).order(:created_at).each(&:destroy!)
    end

    def with_lock
      FileUtils.mkdir_p(lock_path.dirname)
      File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |file|
        file.flock(File::LOCK_EX)
        yield
      ensure
        file&.flock(File::LOCK_UN)
      end
    end

    def lock_path
      host_root.join("tmp", "ruby_sage.lock")
    end

    def detect_git_sha
      command = ["git", "-C", host_root.to_s, "rev-parse", "HEAD"]
      sha = IO.popen(command, err: File::NULL, &:read).to_s.strip
      sha.presence
    rescue SystemCallError, IOError
      nil
    end
  end
end
