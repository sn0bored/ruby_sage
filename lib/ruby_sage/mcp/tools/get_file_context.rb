# frozen_string_literal: true

require "ruby_sage/mcp/tools/base"

module RubySage
  module MCP
    module Tools
      # Returns compact signatures or full file contents for a host-relative path.
      class GetFileContext < Base
        NAME = "get_file_context"
        DESCRIPTION = "Return a file signature from RubySage artifacts or the full host file contents."
        INPUT_SCHEMA = {
          "type" => "object",
          "properties" => {
            "path" => {
              "type" => "string",
              "description" => "Host-root-relative file path."
            },
            "mode" => {
              "type" => "string",
              "enum" => %w[full signature],
              "description" => "Return full source text or compact signature text."
            }
          },
          "required" => ["path"],
          "additionalProperties" => false
        }.freeze

        # @param arguments [Hash] tool arguments.
        # @return [String, nil] file context, or nil when the file/artifact is missing.
        def call(arguments)
          path = require_string(arguments, "path")
          mode = value_for(arguments, "mode") || "signature"
          raise ArgumentError, "mode must be `full` or `signature`" unless %w[full signature].include?(mode)

          mode == "full" ? full_context(path) : signature_context(path)
        end

        private

        def full_context(path)
          file = host_file_path(path)
          return nil unless file.file?

          file.read
        end

        def signature_context(path)
          payload = disk_store.read_artifact(path: relative_path!(path))
          return nil if payload.nil?

          SignatureFormatter.new(payload: payload).call
        end

        # Formats artifact signatures as a compact, readable text block.
        class SignatureFormatter
          # @param payload [Hash] artifact payload read from disk.
          def initialize(payload:)
            @payload = payload
          end

          # @return [String] formatted signature text.
          def call
            sections = []
            append_classes(sections)
            append_methods(sections)
            append_active_record(sections)
            append_constants(sections)
            sections.empty? ? "No signature available." : sections.join("\n")
          end

          private

          attr_reader :payload

          def append_classes(sections)
            lines = classes.map { |entry| class_line(entry) }
            append_section(sections, "Classes", lines)
          end

          def append_methods(sections)
            lines = methods.map { |entry| method_line(entry) }
            append_section(sections, "Methods", lines)
          end

          def append_active_record(sections)
            lines = associations + validations + enums + scopes
            append_section(sections, "ActiveRecord", lines)
          end

          def append_constants(sections)
            lines = Array(value_for(signature, :constants)).map { |name| "- #{name}" }
            append_section(sections, "Constants", lines)
          end

          def append_section(sections, title, lines)
            return if lines.empty?

            sections << (["#{title}:"] + lines).join("\n")
          end

          def class_line(entry)
            name = value_for(entry, :name)
            superclass = value_for(entry, :superclass)
            mixins = mixin_summary(entry)
            line = "- #{name}"
            line = "#{line} < #{superclass}" unless superclass.nil? || superclass.to_s.empty?
            mixins.empty? ? line : "#{line} (#{mixins})"
          end

          def mixin_summary(entry)
            [
              mixin_part(entry, :includes, "includes"),
              mixin_part(entry, :extends, "extends"),
              mixin_part(entry, :prepends, "prepends")
            ].compact.join("; ")
          end

          def mixin_part(entry, key, label)
            values = Array(value_for(entry, key))
            return nil if values.empty?

            "#{label} #{values.join(', ')}"
          end

          def method_line(entry)
            receiver = value_for(entry, :receiver) || "instance"
            visibility = value_for(entry, :visibility) || "public"
            name = value_for(entry, :name)
            params = format_params(Array(value_for(entry, :params)))
            "- #{receiver} #{visibility} #{name}(#{params})"
          end

          def format_params(params)
            params.filter_map { |param| format_param(param) }.join(", ")
          end

          def format_param(param)
            name = value_for(param, :name)
            kind = value_for(param, :kind)
            return name if %w[req opt].include?(kind)
            return "#{name}:" if %w[keyreq key].include?(kind)

            prefixed_param(kind, name)
          end

          def prefixed_param(kind, name)
            return "*#{name}" if kind == "rest"
            return "**#{name}" if kind == "kwrest"
            return "&#{name || 'block'}" if kind == "block"
            return "..." if kind == "forward"
            return "**nil" if kind == "nokey"

            name
          end

          def associations
            active_record_entries(:associations).map do |entry|
              "- #{value_for(entry, :kind)} :#{value_for(entry, :name)}#{options_suffix(entry)}"
            end
          end

          def validations
            active_record_entries(:validations).map do |entry|
              "- validates #{Array(value_for(entry, :fields)).join(', ')} #{value_for(entry, :kind)}"
            end
          end

          def enums
            active_record_entries(:enums).map do |entry|
              "- enum #{value_for(entry, :name)}: #{Array(value_for(entry, :values)).join(', ')}"
            end
          end

          def scopes
            active_record_entries(:scopes).map do |entry|
              "- scope #{value_for(entry, :name)}(#{format_params(Array(value_for(entry, :params)))})"
            end
          end

          def options_suffix(entry)
            options = value_for(entry, :options) || {}
            return "" if options.empty?

            " #{options.map { |key, value| "#{key}: #{value}" }.join(', ')}"
          end

          def active_record_entries(key)
            Array(value_for(active_record, key))
          end

          def classes
            Array(value_for(signature, :classes))
          end

          def methods
            Array(value_for(signature, :methods))
          end

          def active_record
            value_for(signature, :activerecord) || {}
          end

          def signature
            value_for(payload, :signature) || {}
          end

          def value_for(hash, key)
            return nil unless hash.respond_to?(:key?)

            [key, key.to_s, key.to_sym].uniq.each do |candidate|
              return hash[candidate] if hash.key?(candidate)
            end
            nil
          end
        end
        private_constant :SignatureFormatter
      end
    end
  end
end
