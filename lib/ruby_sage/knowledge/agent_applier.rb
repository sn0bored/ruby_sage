# frozen_string_literal: true

require "fileutils"
require "pathname"
require "yaml"

module RubySage
  module Knowledge
    # Copies an agent-authored +knowledge.yml+ from +tmp/ruby_sage+ into the
    # host's +config/ruby_sage/knowledge/seeded.yml+ so the entries become
    # version-controlled. The caller is expected to run +knowledge:sync+
    # afterward to upsert.
    class AgentApplier
      INPUT_FILENAME = "knowledge.yml"
      DESTINATION_FILENAME = "seeded.yml"

      class MissingInput < StandardError; end
      class InvalidInput < StandardError; end

      # @param host_root [String, Pathname]
      # @param output_dir [String, Pathname]
      def initialize(host_root:, output_dir:)
        @host_root = Pathname(host_root).expand_path
        @output_dir = Pathname(output_dir).expand_path
      end

      # @return [Hash]
      def run
        input_path = @output_dir.join(INPUT_FILENAME)
        raise MissingInput, "Expected #{input_path} (agent should have written it)" unless input_path.exist?

        contents = File.read(input_path)
        entries = parse(contents)

        destination = Knowledge.path.join(DESTINATION_FILENAME)
        FileUtils.mkdir_p(destination.dirname)
        File.write(destination, contents)

        {
          destination_path: destination.to_s,
          entry_count: entries.size
        }
      end

      private

      def parse(contents)
        data = YAML.safe_load(contents, permitted_classes: [Date, Time, Symbol], aliases: true)
        case data
        when Array then data
        when Hash  then Array(data["entries"])
        else
          raise InvalidInput, "knowledge.yml must be a top-level array or { entries: [...] } hash"
        end
      end
    end
  end
end
