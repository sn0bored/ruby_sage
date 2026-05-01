# frozen_string_literal: true

require "digest"
require "pathname"

module RubySage
  class Scanner
    # Builds persisted artifacts from sanitized file contents.
    class ArtifactBuilder
      PATH_KIND_PREFIXES = {
        "app/models/" => "model",
        "app/controllers/" => "controller",
        "app/services/" => "service",
        "app/jobs/" => "job",
        "app/mailers/" => "mailer",
        "app/policies/" => "policy",
        "app/queries/" => "query",
        "app/serializers/" => "serializer",
        "app/decorators/" => "decorator",
        "app/helpers/" => "helper",
        "app/components/" => "component",
        "app/workers/" => "worker",
        "app/views/" => "view"
      }.freeze

      SYMBOL_PATTERN = /
        \A\s*
        (?:
          (?:class|module)\s+(?<constant>[A-Z]\w*(?:::[A-Z]\w*)*) |
          def\s+(?:self\.)?(?<method>[a-zA-Z_]\w*[!?=]?)
        )
      /x.freeze

      # Initializes a builder for paths under one host root.
      #
      # @param host_root [String, Pathname]
      # @return [RubySage::Scanner::ArtifactBuilder]
      def initialize(host_root:)
        @host_root = Pathname(host_root).expand_path
      end

      # Creates one Artifact and returns it with its sanitized contents.
      #
      # @param scan [RubySage::Scan]
      # @param path [Pathname]
      # @return [Hash] artifact and redacted contents for the summary pass.
      def build(scan:, path:)
        contents = sanitized_contents(path)
        artifact = Artifact.create!(artifact_attributes(scan, path, contents))

        { artifact: artifact, contents: contents }
      end

      private

      attr_reader :host_root

      def sanitized_contents(path)
        SecretRedactor.new(File.read(path)).call
      end

      def artifact_attributes(scan, path, contents)
        {
          scan: scan,
          path: relative_path(path),
          kind: classify(path),
          digest: Digest::SHA256.hexdigest(contents),
          summary: nil,
          public_symbols: extract_symbols(contents),
          route_mappings: nil
        }
      end

      def relative_path(path)
        path.expand_path.relative_path_from(host_root).to_s
      end

      def classify(path)
        relative = relative_path(path)
        PATH_KIND_PREFIXES.each do |prefix, kind|
          return kind if relative.start_with?(prefix)
        end
        special_kind(relative)
      end

      def special_kind(relative)
        return "routes" if relative == "config/routes.rb"
        return "schema" if relative == "db/schema.rb"
        return "readme" if relative == "README.md"
        return "instructions" if relative == "CLAUDE.md"
        return "rules" if relative == ".cursorrules"

        "other"
      end

      def extract_symbols(contents)
        contents.each_line.filter_map do |line|
          match = line.match(SYMBOL_PATTERN)
          match&.[](:constant) || match&.[](:method)
        end.uniq
      end
    end
  end
end
