# frozen_string_literal: true

require "ruby_sage/mcp/tools/base"

module RubySage
  module MCP
    module Tools
      # Reports whether the disk index has a completed manifest.
      class IndexStatus < Base
        NAME = "index_status"
        DESCRIPTION = "Report RubySage disk index metadata from manifest.json."
        INPUT_SCHEMA = {
          "type" => "object",
          "additionalProperties" => false
        }.freeze

        # @param _arguments [Hash] ignored tool arguments.
        # @return [Hash] index manifest metadata and freshness.
        def call(_arguments)
          manifest = disk_store.read_manifest
          finished_at = value_for(manifest, :finished_at)
          {
            "git_sha" => value_for(manifest, :git_sha),
            "ruby_version" => value_for(manifest, :ruby_version),
            "rails_version" => value_for(manifest, :rails_version),
            "file_count" => file_count(manifest),
            "finished_at" => finished_at,
            "fresh" => !manifest.nil? && !finished_at.to_s.empty?
          }
        end

        private

        def file_count(manifest)
          value = value_for(manifest, :file_count)
          value.nil? ? 0 : value.to_i
        end
      end
    end
  end
end
