# frozen_string_literal: true

require "fileutils"
require "pathname"
require "ruby_sage/secret_redactor"
require "ruby_sage/scanner/artifact_builder"
require "ruby_sage/scanner/walker"
require "ruby_sage/summarizer"

module RubySage
  # Walks the host app filesystem and produces a Scan with associated Artifacts.
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
    def initialize(host_root:, config: RubySage.configuration)
      @host_root = Pathname(host_root).expand_path
      @config = config
    end

    # Runs a locked filesystem scan and persists scan artifacts.
    #
    # @return [RubySage::Scan]
    def run
      with_lock { create_scan }
    end

    private

    attr_reader :host_root, :config

    def create_scan
      scan = nil
      previous_artifacts = latest_completed_artifacts_by_path
      scan = start_scan
      finish_scan(scan, previous_artifacts)
    rescue StandardError => e
      scan&.update!(status: "failed", errors_log: e.full_message)
      raise
    end

    def finish_scan(scan, previous_artifacts)
      artifact_inputs = create_artifacts(scan)
      summarize_artifacts(artifact_inputs, previous_artifacts)
      complete_scan(scan)
      prune_old_scans
      scan
    end

    def start_scan
      Scan.create!(
        status: "running",
        started_at: Time.current,
        git_sha: detect_git_sha,
        ruby_version: RUBY_VERSION,
        rails_version: Rails::VERSION::STRING
      )
    end

    def create_artifacts(scan)
      artifact_builder = ArtifactBuilder.new(host_root: host_root)
      Walker.new(host_root: host_root, config: config).paths.map do |path|
        artifact_builder.build(scan: scan, path: path)
      end
    end

    def summarize_artifacts(artifact_inputs, previous_artifacts)
      summarizer = Summarizer.new(config: config)
      artifact_inputs.each do |input|
        summary = summary_for(input[:artifact], input[:contents], previous_artifacts, summarizer)
        input[:artifact].update!(summary: summary) unless summary.nil?
      end
    end

    def summary_for(artifact, contents, previous_artifacts, summarizer)
      previous = previous_artifacts[artifact.path]
      return previous.summary if previous&.digest == artifact.digest

      summarizer.summarize(contents: contents, path: artifact.path)
    end

    def complete_scan(scan)
      scan.update!(
        status: "completed",
        finished_at: Time.current,
        file_count: scan.artifacts.count
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
