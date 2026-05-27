# frozen_string_literal: true

module RubySage
  module Artifacts
    # Serializes artifact + manifest payloads to the on-disk schema and reads
    # YAML/JSON back into symbol-keyed hashes.
    #
    # Pulled out of {DiskStore} so the I/O class owns paths and files while
    # this module owns "what does the disk format look like."
    module Serializer
      module_function

      # @param path [String]
      # @param attributes [Hash]
      # @param schema_version [Integer]
      # @return [Hash] artifact payload ready for `YAML.dump`.
      def artifact_payload(path:, attributes:, schema_version:)
        {
          "schema_version" => schema_version,
          "path" => path,
          "kind" => attributes[:kind],
          "digest" => attributes[:digest],
          "summary" => attributes[:summary],
          "signature" => json_value(attributes[:signature]),
          "public_symbols" => Array(attributes[:public_symbols]).map(&:to_s),
          "route_mappings" => attributes[:route_mappings],
          "audiences" => Array(attributes[:audiences]).map(&:to_s)
        }
      end

      # @param attributes [Hash]
      # @param schema_version [Integer]
      # @return [Hash] manifest payload ready for `JSON.dump`.
      def manifest_payload(attributes:, schema_version:)
        {
          "schema_version" => schema_version,
          "git_sha" => attributes[:git_sha],
          "ruby_version" => attributes[:ruby_version],
          "rails_version" => attributes[:rails_version],
          "started_at" => iso8601(attributes[:started_at]),
          "finished_at" => iso8601(attributes[:finished_at]),
          "file_count" => attributes[:file_count],
          "scanner" => attributes[:scanner]
        }
      end

      # @param pathname [Pathname]
      # @return [Hash] YAML-decoded payload with symbol keys.
      def load_yaml(pathname)
        raw = YAML.safe_load(File.read(pathname), permitted_classes: [], aliases: false) || {}
        raw.transform_keys(&:to_sym)
      end

      def iso8601(time)
        return nil if time.nil?
        return time if time.is_a?(String)

        time.iso8601
      end

      def json_value(value)
        return value.map { |entry| json_value(entry) } if value.is_a?(Array)

        return json_hash(value) if value.is_a?(Hash)

        value
      end

      def json_hash(value)
        value.each_with_object({}) do |(key, entry), result|
          result[key.to_s] = json_value(entry)
        end
      end
    end
  end
end
