# frozen_string_literal: true

require "fileutils"
require "json"
require "pathname"
require "time"
require "ruby_sage/scanner/walker"
require "ruby_sage/scanner/artifact_builder"

module RubySage
  module AgentScan
    # Walks the host app and writes a manifest a coding agent can summarize
    # without burning gem-attributable API tokens. Reuses summaries from the
    # latest completed scan when a file digest is unchanged.
    class Planner
      # Initializes a planner for the host app.
      #
      # @param host_root [String, Pathname]
      # @param config [RubySage::Configuration]
      # @param output_dir [String, Pathname, nil] where +manifest.json+ and
      #   +INSTRUCTIONS.md+ will be written. Defaults to
      #   +<host_root>/tmp/ruby_sage+.
      # @return [RubySage::AgentScan::Planner]
      def initialize(host_root:, config: RubySage.configuration, output_dir: nil)
        @host_root = Pathname(host_root).expand_path
        @config = config
        @output_dir = output_dir ? Pathname(output_dir).expand_path : default_output_dir
      end

      # Builds the manifest, writes +manifest.json+ + +INSTRUCTIONS.md+, and
      # returns a result hash with the written paths and counts.
      #
      # @return [Hash]
      def run
        FileUtils.mkdir_p(output_dir)

        manifest = build_manifest
        manifest_path = output_dir.join(MANIFEST_FILENAME)
        instructions_path = output_dir.join(INSTRUCTIONS_FILENAME)

        File.write(manifest_path, "#{JSON.pretty_generate(manifest)}\n")
        File.write(instructions_path, Instructions.new(manifest: manifest, output_dir: output_dir).render)

        {
          manifest_path: manifest_path.to_s,
          instructions_path: instructions_path.to_s,
          summaries_path: output_dir.join(SUMMARIES_FILENAME).to_s,
          file_count: manifest["files"].size,
          needs_summary_count: manifest["files"].count { |entry| entry["needs_summary"] }
        }
      end

      private

      attr_reader :host_root, :config, :output_dir

      def default_output_dir
        host_root.join(DEFAULT_OUTPUT_DIRNAME)
      end

      def build_manifest
        previous_artifacts = latest_completed_artifacts_by_path
        builder = Scanner::ArtifactBuilder.new(host_root: host_root)
        files = Scanner::Walker.new(host_root: host_root, config: config).paths.map do |path|
          file_entry(builder, path, previous_artifacts)
        end

        {
          "schema_version" => SCHEMA_VERSION,
          "generated_at" => Time.now.utc.iso8601,
          "git_sha" => detect_git_sha,
          "ruby_version" => RUBY_VERSION,
          "rails_version" => Rails::VERSION::STRING,
          "summary_system_prompt" => Summarizer::SUMMARY_SYSTEM_PROMPT.strip,
          "files" => files
        }
      end

      def file_entry(builder, path, previous_artifacts)
        attrs = builder.attributes_for(path: path)
        artifact_attributes = attrs[:artifact_attributes]
        previous = previous_artifacts[artifact_attributes[:path]]
        cached_summary = previous && previous.digest == artifact_attributes[:digest] ? previous.summary : nil

        {
          "path" => artifact_attributes[:path],
          "kind" => artifact_attributes[:kind],
          "digest" => artifact_attributes[:digest],
          "public_symbols" => artifact_attributes[:public_symbols],
          "audiences" => Array(artifact_attributes[:audiences]),
          "redacted_contents" => attrs[:contents],
          "previous_summary" => cached_summary,
          "needs_summary" => cached_summary.nil?
        }
      end

      def latest_completed_artifacts_by_path
        latest_scan = Scan.latest_completed.first
        return {} if latest_scan.nil?

        latest_scan.artifacts.index_by(&:path)
      end

      def detect_git_sha
        command = ["git", "-C", host_root.to_s, "rev-parse", "HEAD"]
        sha = IO.popen(command, err: File::NULL, &:read).to_s.strip
        sha.empty? ? nil : sha
      rescue SystemCallError, IOError
        nil
      end
    end
  end
end
