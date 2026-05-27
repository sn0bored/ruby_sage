# frozen_string_literal: true

require "json"
require "pathname"

module RubySage
  module MCP
    module Tools
      # Shared helpers for disk-backed MCP tools.
      class Base
        # @param host_root [String, Pathname] root directory of the host app.
        # @param disk_store [RubySage::Artifacts::DiskStore] disk artifact reader.
        def initialize(host_root:, disk_store:)
          @host_root = Pathname(host_root).expand_path
          @disk_store = disk_store
        end

        private

        attr_reader :host_root, :disk_store

        def require_string(arguments, key)
          value = value_for(arguments, key)
          raise ArgumentError, "#{key} is required" if value.nil? || value.to_s.strip.empty?

          value.to_s
        end

        def integer_argument(arguments, key, default)
          value = value_for(arguments, key)
          return default if value.nil?

          Integer(value)
        rescue ArgumentError, TypeError
          raise ArgumentError, "#{key} must be a number"
        end

        def value_for(hash, key)
          return nil unless hash.respond_to?(:key?)

          lookup_keys(key).each do |candidate|
            return hash[candidate] if hash.key?(candidate)
          end
          nil
        end

        def lookup_keys(key)
          [key, key.to_s, key.to_sym].uniq
        end

        def relative_path!(path)
          value = path.to_s
          if value.empty? || value == "." || value.include?("\0") || value.start_with?("/") || value.include?("..")
            raise ArgumentError, "path must be host-relative without `..`: #{path.inspect}"
          end

          value
        end

        def host_file_path(path)
          relative = relative_path!(path)
          candidate = host_root.join(relative).cleanpath
          raise ArgumentError, "path escapes host root: #{path.inspect}" unless within_host_root?(candidate)

          candidate
        end

        def within_host_root?(candidate)
          candidate.to_s == host_root.to_s || candidate.to_s.start_with?("#{host_root}/")
        end

        def read_routes
          path = host_root.join(".ruby_sage", "routes.json")
          return [] unless path.file?

          payload = JSON.parse(path.read)
          Array(value_for(payload, "routes"))
        rescue JSON::ParserError
          []
        end

        def signature_for(payload)
          value_for(payload, :signature) || {}
        end

        def signature_classes(payload)
          Array(value_for(signature_for(payload), :classes))
        end

        def signature_methods(payload)
          Array(value_for(signature_for(payload), :methods))
        end
      end
    end
  end
end
