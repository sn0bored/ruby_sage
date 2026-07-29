# frozen_string_literal: true

require "yaml"

module RubySage
  module Knowledge
    # Reads YAML files from a knowledge directory and returns a flat array
    # of entry hashes with stringified keys.
    #
    # Each YAML file under the configured path must contain either:
    #
    # - a top-level array of entry hashes, or
    # - a top-level hash with an +"entries"+ key whose value is the array.
    #
    # Both shapes coexist so a file can carry per-file metadata (e.g.
    # +category:+, +source_file:+) without making each entry repeat it.
    class Loader
      REQUIRED_KEYS = %w[slug title body].freeze

      class InvalidFile < StandardError; end

      # @param path [Pathname, String]
      def initialize(path: Knowledge.path)
        @path = Pathname.new(path.to_s)
      end

      # @return [Array<Hash>]
      def load
        return [] unless @path.exist?

        Dir.glob(@path.join("*.{yml,yaml}").to_s).flat_map do |file|
          load_file(file)
        end
      end

      private

      def load_file(file)
        data = YAML.safe_load_file(file, permitted_classes: [Date, Time, Symbol], aliases: true)
        entries = extract_entries(data)
        entries.map { |entry| normalize_entry(entry, file) }
      rescue Psych::Exception => e
        raise InvalidFile, "Could not parse #{file}: #{e.message}"
      end

      def extract_entries(data)
        return data if data.is_a?(Array)
        return Array(data["entries"]) if data.is_a?(Hash) && data["entries"]

        raise InvalidFile, "Expected a top-level array or { entries: [...] } hash"
      end

      def normalize_entry(entry, file)
        raise InvalidFile, "#{file}: each entry must be a hash, got #{entry.class}" unless entry.is_a?(Hash)

        stringified = entry.transform_keys(&:to_s)
        missing = REQUIRED_KEYS - stringified.keys
        raise InvalidFile, "#{file}: entry missing required keys: #{missing.join(', ')}" unless missing.empty?

        stringified["source_file"] = file
        stringified
      end
    end
  end
end
