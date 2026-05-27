# frozen_string_literal: true

require "fileutils"
require "find"
require "forwardable"
require "json"
require "pathname"
require "set"
require "yaml"

require "ruby_sage/artifacts/layout"
require "ruby_sage/artifacts/serializer"

module RubySage
  module Artifacts
    # Reads and writes the on-disk artifact layout under `<host_root>/.ruby_sage/`.
    #
    # Layout:
    #
    #   .ruby_sage/
    #   ├── manifest.json             scan metadata (sha, ruby/rails versions, file count)
    #   ├── artifacts/
    #   │   └── app/models/user.rb.yml  signatures + digest, mirrors host file tree
    #   ├── routes.json               (written in Phase C)
    #   └── .gitignore
    #
    # The disk layout is the source of truth. The widget's database is rebuilt
    # from it via {RubySage::Indexer}.
    #
    # @example Write an artifact and read it back
    #   store = RubySage::Artifacts::DiskStore.new(host_root: Rails.root)
    #   store.write_artifact(path: "app/models/user.rb", attributes: {...})
    #   store.read_artifact(path: "app/models/user.rb") # => {...}
    class DiskStore
      extend Forwardable

      SCHEMA_VERSION = 1

      # @!method root
      #   @return [Pathname] absolute path to `.ruby_sage/`.
      # @!method artifacts_root
      #   @return [Pathname] absolute path to `.ruby_sage/artifacts/`.
      # @!method manifest_path
      #   @return [Pathname] absolute path to `.ruby_sage/manifest.json`.
      def_delegators :@layout, :root, :artifacts_root, :manifest_path

      # @param host_root [String, Pathname] root directory of the host app.
      def initialize(host_root:)
        @layout = Layout.new(host_root: host_root)
      end

      # Creates `.ruby_sage/` + `artifacts/` and seeds `.gitignore` if missing.
      #
      # @return [void]
      def ensure_layout
        layout.ensure
      end

      # Writes one artifact file. Creates any intermediate directories.
      #
      # @param path [String] host-root-relative file path (e.g. "app/models/user.rb").
      # @param attributes [Hash] keys :kind, :digest, :summary, :public_symbols,
      #   :route_mappings, :audiences. Extra keys are preserved.
      # @return [Pathname] the artifact file written.
      def write_artifact(path:, attributes:)
        guard_relative!(path)
        target = layout.artifact_path_for(path)
        FileUtils.mkdir_p(target.dirname)
        File.write(target, YAML.dump(artifact_payload(path, attributes)))
        target
      end

      # Reads one artifact file by host-relative path.
      #
      # @param path [String]
      # @return [Hash, nil] artifact payload with symbol keys, or nil if missing.
      def read_artifact(path:)
        guard_relative!(path)
        target = layout.artifact_path_for(path)
        return nil unless target.file?

        Serializer.load_yaml(target)
      end

      # Removes an artifact file. No-op if missing.
      #
      # @param path [String]
      # @return [Boolean] true if a file was removed.
      def delete_artifact(path:) # rubocop:disable Naming/PredicateMethod
        guard_relative!(path)
        target = layout.artifact_path_for(path)
        return false unless target.file?

        target.delete
        true
      end

      # Iterates all artifacts on disk.
      #
      # @yieldparam payload [Hash] artifact payload with symbol keys.
      # @return [Enumerator] when no block given.
      def each_artifact
        return enum_for(:each_artifact) unless block_given?
        return unless artifacts_root.directory?

        Find.find(artifacts_root.to_s) do |candidate|
          next unless artifact_file?(candidate)

          yield Serializer.load_yaml(Pathname(candidate))
        end
      end

      # @return [Array<String>] host-relative paths for every artifact on disk.
      def artifact_paths
        return [] unless artifacts_root.directory?

        paths = []
        Find.find(artifacts_root.to_s) do |candidate|
          paths << layout.relative_to_artifacts(candidate) if artifact_file?(candidate)
        end
        paths.sort
      end

      # Deletes any on-disk artifact whose host-relative path is not in +paths+.
      # Use after a scan to drop stale files.
      #
      # @param paths [Enumerable<String>]
      # @return [Integer] number of artifacts deleted.
      def prune_artifacts_outside(paths)
        return 0 unless artifacts_root.directory?

        kept = paths.to_set
        deleted = 0
        Find.find(artifacts_root.to_s) do |candidate|
          next unless artifact_file?(candidate)
          next if kept.include?(layout.relative_to_artifacts(candidate))

          File.delete(candidate)
          deleted += 1
        end
        layout.prune_empty_artifact_dirs
        deleted
      end

      # Writes `manifest.json`.
      #
      # @param attributes [Hash] keys :git_sha, :ruby_version, :rails_version,
      #   :started_at, :finished_at, :file_count, :scanner. Times serialize to ISO-8601.
      # @return [Pathname]
      def write_manifest(attributes:)
        ensure_layout
        File.write(manifest_path, JSON.pretty_generate(manifest_payload(attributes)))
        manifest_path
      end

      # @return [Hash, nil] manifest payload with symbol keys, or nil if missing.
      def read_manifest
        return nil unless manifest_path.file?

        JSON.parse(File.read(manifest_path)).transform_keys(&:to_sym)
      end

      private

      attr_reader :layout

      def artifact_payload(path, attributes)
        Serializer.artifact_payload(
          path: path, attributes: attributes, schema_version: SCHEMA_VERSION
        )
      end

      def manifest_payload(attributes)
        Serializer.manifest_payload(attributes: attributes, schema_version: SCHEMA_VERSION)
      end

      def artifact_file?(candidate)
        candidate.end_with?(Layout::ARTIFACT_EXTENSION) && File.file?(candidate)
      end

      def guard_relative!(path)
        return unless path.to_s.empty? || path.start_with?("/") || path.include?("..")

        raise ArgumentError, "DiskStore path must be host-relative without `..`: #{path.inspect}"
      end
    end
  end
end
