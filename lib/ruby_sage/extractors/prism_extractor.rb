# frozen_string_literal: true

require "pathname"
require "prism"

module RubySage
  module Extractors
    # Extracts structural Ruby signatures with Prism without requiring host code.
    class PrismExtractor
      # @param path [String, Pathname, nil] Ruby file path to read when
      #   +contents+ is not supplied.
      # @param contents [String, nil] source text to parse.
      # @return [RubySage::Extractors::PrismExtractor]
      def initialize(path: nil, contents: nil)
        @path = path.nil? ? nil : Pathname(path)
        @contents = contents
      end

      # Parses the Ruby source and returns a structural signature hash.
      #
      # @return [Hash]
      def call
        parsed = Prism.parse(source)
        return empty_signature unless parsed.success?

        SignatureVisitor.new.call(parsed.value)
      rescue Errno::ENOENT, EncodingError
        empty_signature
      end

      private

      attr_reader :path, :contents

      def source
        return contents unless contents.nil?

        File.read(path)
      end

      def empty_signature
        {
          classes: [],
          methods: [],
          activerecord: {
            associations: [],
            validations: [],
            enums: [],
            scopes: []
          },
          constants: []
        }
      end

      # Converts Prism constant path nodes into static names.
      module ConstantName
        module_function

        # @param node [Prism::Node, nil]
        # @return [String, nil]
        def call(node)
          return nil if node.nil?
          return node.name.to_s if node.is_a?(Prism::ConstantReadNode)

          constant_path_name(node)
        end

        # @param node [Prism::Node, nil]
        # @return [Boolean]
        def absolute?(node)
          node.is_a?(Prism::ConstantPathNode) && node.parent.nil?
        end

        def constant_path_name(node)
          return nil unless node.is_a?(Prism::ConstantPathNode)

          parent_name = call(node.parent)
          [parent_name, node.name.to_s].compact.join("::")
        end
      end
      private_constant :ConstantName

      # Converts Prism literal nodes into JSON-compatible Ruby values.
      class LiteralExtractor
        UNHANDLED = Object.new.freeze

        # @param node [Prism::Node, nil]
        # @return [Object, nil]
        def self.call(node)
          new.call(node)
        end

        # @param node [Prism::Node, nil]
        # @return [Object, nil]
        def call(node)
          literal = literal_node_value(node)
          return literal unless literal.equal?(UNHANDLED)

          compound = compound_node_value(node)
          return compound unless compound.equal?(UNHANDLED)

          ConstantName.call(node)
        end

        private

        def literal_node_value(node)
          value = text_node_value(node)
          return value unless value.equal?(UNHANDLED)

          value = numeric_node_value(node)
          return value unless value.equal?(UNHANDLED)

          boolean_or_nil_node_value(node)
        end

        def text_node_value(node)
          return node.unescaped if node.is_a?(Prism::SymbolNode) || node.is_a?(Prism::StringNode)

          UNHANDLED
        end

        def numeric_node_value(node)
          return node.value if node.is_a?(Prism::IntegerNode) || node.is_a?(Prism::FloatNode)

          UNHANDLED
        end

        def boolean_or_nil_node_value(node)
          return true if node.is_a?(Prism::TrueNode)
          return false if node.is_a?(Prism::FalseNode)
          return nil if node.is_a?(Prism::NilNode)

          UNHANDLED
        end

        def compound_node_value(node)
          return array_value(node) if node.is_a?(Prism::ArrayNode)
          return hash_value(node) if node.is_a?(Prism::HashNode) || node.is_a?(Prism::KeywordHashNode)

          UNHANDLED
        end

        def array_value(node)
          node.elements.filter_map { |element| self.class.call(element) }
        end

        def hash_value(node)
          node.elements.each_with_object({}) do |element, result|
            next unless element.is_a?(Prism::AssocNode)

            key = self.class.call(element.key)
            result[hash_key(key, element.key)] = self.class.call(element.value) unless key.nil?
          end
        end

        def hash_key(key, node)
          return key.to_sym if node.is_a?(Prism::SymbolNode)

          key.to_s
        end
      end
      private_constant :LiteralExtractor

      # Extracts normalized parameter metadata and Ruby-compatible arity.
      class ParameterExtractor
        # @param parameters [Prism::ParametersNode, Prism::BlockParametersNode, nil]
        # @return [RubySage::Extractors::PrismExtractor::ParameterExtractor]
        def initialize(parameters)
          @parameters = normalize_parameters(parameters)
        end

        # @return [Array<Hash>]
        def call
          return [] if parameters.nil?

          positional_params + rest_param + post_params + keyword_params + keyword_rest_param + block_param
        end

        # @return [Integer]
        def arity
          return 0 if parameters.nil?

          required = required_positional_count
          required += 1 if required_keyword_params.any?
          optional_arguments? ? -(required + 1) : required
        end

        private

        attr_reader :parameters

        def normalize_parameters(parameters)
          return nil if parameters.nil?
          return parameters.parameters if parameters.is_a?(Prism::BlockParametersNode)

          parameters
        end

        def positional_params
          required_params(parameters.requireds, "req") +
            required_params(parameters.optionals, "opt")
        end

        def post_params
          required_params(parameters.posts, "req")
        end

        def required_params(nodes, kind)
          nodes.map { |node| parameter_hash(node.name, kind) }
        end

        def rest_param
          return [] if parameters.rest.nil?

          [parameter_hash(parameters.rest.name, "rest")]
        end

        def keyword_params
          parameters.keywords.map do |node|
            kind = node.is_a?(Prism::RequiredKeywordParameterNode) ? "keyreq" : "key"
            parameter_hash(node.name, kind)
          end
        end

        def keyword_rest_param
          return [] if parameters.keyword_rest.nil?

          [parameter_hash(keyword_rest_name, keyword_rest_kind)]
        end

        def block_param
          return [] if parameters.block.nil?

          [parameter_hash(parameters.block.name, "block")]
        end

        def keyword_rest_name
          parameters.keyword_rest.respond_to?(:name) ? parameters.keyword_rest.name : nil
        end

        def keyword_rest_kind
          return "forward" if parameters.keyword_rest.is_a?(Prism::ForwardingParameterNode)
          return "nokey" if parameters.keyword_rest.is_a?(Prism::NoKeywordsParameterNode)

          "kwrest"
        end

        def parameter_hash(name, kind)
          { name: name&.to_s, kind: kind }
        end

        def required_positional_count
          parameters.requireds.size + parameters.posts.size
        end

        def required_keyword_params
          parameters.keywords.grep(Prism::RequiredKeywordParameterNode)
        end

        def optional_arguments?
          parameters.optionals.any? ||
            !parameters.rest.nil? ||
            optional_keyword_params? ||
            optional_keyword_rest?
        end

        def optional_keyword_params?
          parameters.keywords.any?(Prism::OptionalKeywordParameterNode)
        end

        def optional_keyword_rest?
          !parameters.keyword_rest.nil? && required_keyword_params.empty?
        end
      end
      private_constant :ParameterExtractor

      # Walks the Prism AST and accumulates the RubySage signature schema.
      # rubocop:disable Metrics/ClassLength
      class SignatureVisitor
        CLASS_CALL_HANDLERS = {
          belongs_to: :record_association,
          enum: :record_enum,
          extend: :apply_mixin,
          has_and_belongs_to_many: :record_association,
          has_many: :record_association,
          has_one: :record_association,
          include: :apply_mixin,
          prepend: :apply_mixin,
          private: :apply_visibility,
          protected: :apply_visibility,
          public: :apply_visibility,
          scope: :record_scope,
          validates: :record_validates,
          validates_absence_of: :record_validation_helper,
          validates_acceptance_of: :record_validation_helper,
          validates_confirmation_of: :record_validation_helper,
          validates_exclusion_of: :record_validation_helper,
          validates_format_of: :record_validation_helper,
          validates_inclusion_of: :record_validation_helper,
          validates_length_of: :record_validation_helper,
          validates_numericality_of: :record_validation_helper,
          validates_presence_of: :record_validation_helper,
          validates_uniqueness_of: :record_validation_helper
        }.freeze
        CONSTANT_ASSIGNMENT_CLASSES = [
          Prism::ConstantAndWriteNode,
          Prism::ConstantOperatorWriteNode,
          Prism::ConstantOrWriteNode,
          Prism::ConstantPathAndWriteNode,
          Prism::ConstantPathOperatorWriteNode,
          Prism::ConstantPathOrWriteNode,
          Prism::ConstantPathWriteNode,
          Prism::ConstantWriteNode
        ].freeze
        DISPATCH_HANDLERS = [
          [Prism::ProgramNode, :handle_program],
          [Prism::StatementsNode, :handle_statements],
          [Prism::ClassNode, :handle_class_node],
          [Prism::ModuleNode, :handle_module_node],
          [Prism::DefNode, :handle_def_node],
          [Prism::CallNode, :handle_call_node],
          [Prism::SingletonClassNode, :handle_singleton_class_node]
        ].freeze
        HANDLED = Object.new.freeze
        MIXIN_CALLS = {
          include: :includes,
          extend: :extends,
          prepend: :prepends
        }.freeze
        VALIDATION_CALLS = {
          validates_absence_of: "absence",
          validates_acceptance_of: "acceptance",
          validates_confirmation_of: "confirmation",
          validates_exclusion_of: "exclusion",
          validates_format_of: "format",
          validates_inclusion_of: "inclusion",
          validates_length_of: "length",
          validates_numericality_of: "numericality",
          validates_presence_of: "presence",
          validates_uniqueness_of: "uniqueness"
        }.freeze
        VALIDATION_OPTIONS = %i[
          absence acceptance confirmation exclusion format inclusion length
          numericality presence uniqueness
        ].freeze

        # @return [RubySage::Extractors::PrismExtractor::SignatureVisitor]
        def initialize
          @signature = empty_signature
          @class_stack = []
          @namespace_stack = []
          @receiver_stack = ["instance"]
        end

        # @param root [Prism::Node]
        # @return [Hash]
        def call(root)
          visit(root)
          signature[:constants].uniq!
          signature
        end

        private

        attr_reader :signature, :class_stack, :namespace_stack, :receiver_stack

        def empty_signature
          {
            classes: [],
            methods: [],
            activerecord: {
              associations: [],
              validations: [],
              enums: [],
              scopes: []
            },
            constants: []
          }
        end

        def visit(node)
          return if node.nil?

          visit_children(node) unless dispatch_node(node)
        end

        def dispatch_node(node)
          DISPATCH_HANDLERS.each do |node_class, handler|
            return handled(handler, node) if node.is_a?(node_class)
          end
          return handled(:handle_constant_assignment_node, node) if constant_assignment_node?(node)

          nil
        end

        def handled(handler, node)
          __send__(handler, node)
          HANDLED
        end

        def handle_program(node)
          visit(node.statements)
        end

        def visit_children(node)
          node.each_child_node { |child| visit(child) } if node.respond_to?(:each_child_node)
        end

        def handle_statements(node)
          node.body.each { |child| visit(child) }
        end

        def handle_class_node(node)
          name = scoped_constant_name(node.constant_path)
          return if name.nil?

          superclass = ConstantName.call(node.superclass)
          class_info = class_hash(name: name, superclass: superclass)
          signature[:classes] << class_info
          with_class_context(name: name, class_info: class_info) { visit(node.body) }
        end

        def handle_module_node(node)
          name = scoped_constant_name(node.constant_path)
          return if name.nil?

          class_info = class_hash(name: name, superclass: nil)
          signature[:classes] << class_info
          with_class_context(name: name, class_info: class_info) { visit(node.body) }
        end

        def handle_def_node(node)
          extractor = ParameterExtractor.new(node.parameters)
          receiver = method_receiver(node)
          signature[:methods] << {
            name: node.name.to_s,
            receiver: receiver,
            arity: extractor.arity,
            params: extractor.call,
            visibility: method_visibility(receiver: receiver, node: node)
          }
        end

        def handle_call_node(node)
          process_class_call(node) if class_call?(node)
        end

        def handle_singleton_class_node(node)
          return unless node.expression.is_a?(Prism::SelfNode)

          with_receiver("class") { visit(node.body) }
        end

        def handle_constant_assignment_node(node)
          record_top_level_constant(node)
          visit(node.value) if node.respond_to?(:value)
        end

        def class_hash(name:, superclass:)
          {
            name: name,
            superclass: superclass,
            ancestry: [name, superclass].compact,
            includes: [],
            extends: [],
            prepends: []
          }
        end

        def with_class_context(name:, class_info:)
          class_stack.push(
            info: class_info,
            instance_visibility: "public",
            class_visibility: "public"
          )
          namespace_stack.push(name)
          yield
        ensure
          namespace_stack.pop
          class_stack.pop
        end

        def with_receiver(receiver)
          receiver_stack.push(receiver)
          yield
        ensure
          receiver_stack.pop
        end

        def scoped_constant_name(node)
          name = ConstantName.call(node)
          return nil if name.nil?
          return name if ConstantName.absolute?(node) || current_namespace.nil? || name.include?("::")

          "#{current_namespace}::#{name}"
        end

        def current_namespace
          namespace_stack.last
        end

        def current_class
          class_stack.last
        end

        def current_class_info
          current_class && current_class[:info]
        end

        def class_call?(node)
          current_class_info && node.receiver.nil?
        end

        def process_class_call(node)
          handler = CLASS_CALL_HANDLERS[node.name]
          __send__(handler, node) unless handler.nil?
        end

        def apply_visibility(node)
          args = argument_nodes(node)
          return update_visibility(node.name.to_s) if args.empty?

          names = args.filter_map { |arg| LiteralExtractor.call(arg)&.to_s }
          signature[:methods].each do |method|
            method[:visibility] = node.name.to_s if names.include?(method[:name])
          end
        end

        def update_visibility(visibility)
          key = receiver_stack.last == "class" ? :class_visibility : :instance_visibility
          current_class[key] = visibility
        end

        def apply_mixin(node)
          key = MIXIN_CALLS.fetch(node.name)
          current_class_info[key].concat(argument_names(node))
          current_class_info[key].uniq!
        end

        def record_association(node)
          name = LiteralExtractor.call(argument_nodes(node).first)
          return if name.nil?

          signature[:activerecord][:associations] << {
            kind: node.name.to_s,
            name: name.to_s,
            options: options_from(argument_nodes(node).drop(1))
          }
        end

        def record_validates(node)
          args = argument_nodes(node)
          fields = field_names(args)
          validator_options = options_from(args)
          shared_options = shared_validation_options(validator_options)

          validator_options.slice(*VALIDATION_OPTIONS).each do |kind, value|
            record_validation(kind: kind.to_s, fields: fields, value: value, shared_options: shared_options)
          end
        end

        def record_validation_helper(node)
          fields = field_names(argument_nodes(node))
          signature[:activerecord][:validations] << {
            kind: VALIDATION_CALLS.fetch(node.name),
            fields: fields,
            options: options_from(argument_nodes(node))
          }
        end

        def record_validation(kind:, fields:, value:, shared_options:)
          signature[:activerecord][:validations] << {
            kind: kind,
            fields: fields,
            options: validation_options(value).merge(shared_options)
          }
        end

        def record_enum(node)
          enum_pairs(argument_nodes(node)).each do |name, values_node|
            signature[:activerecord][:enums] << {
              name: name.to_s,
              values: enum_values(values_node)
            }
          end
        end

        def record_scope(node)
          args = argument_nodes(node)
          name = LiteralExtractor.call(args.first)
          return if name.nil?

          signature[:activerecord][:scopes] << {
            name: name.to_s,
            params: scope_params(args[1])
          }
        end

        def argument_nodes(node)
          return [] if node.arguments.nil?

          node.arguments.arguments
        end

        def argument_names(node)
          argument_nodes(node).filter_map { |arg| LiteralExtractor.call(arg)&.to_s }
        end

        def options_from(args)
          args.each_with_object({}) do |arg, options|
            next unless hash_argument?(arg)

            options.merge!(LiteralExtractor.call(arg) || {})
          end
        end

        def hash_argument?(node)
          node.is_a?(Prism::HashNode) || node.is_a?(Prism::KeywordHashNode)
        end

        def field_names(args)
          args.reject { |arg| hash_argument?(arg) }
              .filter_map { |arg| LiteralExtractor.call(arg)&.to_s }
        end

        def validation_options(value)
          return {} if value == true
          return value if value.is_a?(Hash)

          { value: value }
        end

        def shared_validation_options(options)
          options.each_with_object({}) do |(key, value), result|
            result[key] = value unless VALIDATION_OPTIONS.include?(key)
          end
        end

        def enum_pairs(args)
          keyword_hash = args.find { |arg| arg.is_a?(Prism::KeywordHashNode) }
          return enum_pairs_from_hash(keyword_hash) unless keyword_hash.nil?

          name = LiteralExtractor.call(args.first)
          name.nil? ? [] : [[name, args[1]]]
        end

        def enum_pairs_from_hash(node)
          node.elements.filter_map do |element|
            next unless element.is_a?(Prism::AssocNode)

            [LiteralExtractor.call(element.key), element.value]
          end
        end

        def enum_values(node)
          return hash_keys(node) if node.is_a?(Prism::HashNode) || node.is_a?(Prism::KeywordHashNode)
          return Array(LiteralExtractor.call(node)).map(&:to_s) if node.is_a?(Prism::ArrayNode)

          []
        end

        def hash_keys(node)
          node.elements.filter_map do |element|
            LiteralExtractor.call(element.key)&.to_s if element.is_a?(Prism::AssocNode)
          end
        end

        def scope_params(node)
          return [] unless node.is_a?(Prism::LambdaNode)

          ParameterExtractor.new(node.parameters).call
        end

        def method_receiver(node)
          return "class" if receiver_stack.last == "class" && node.receiver.nil?
          return "class" unless node.receiver.nil?

          "instance"
        end

        def method_visibility(receiver:, node:)
          return current_class[:class_visibility] if receiver == "class" && node.receiver.nil?
          return current_class[:instance_visibility] if receiver == "instance" && current_class

          "public"
        end

        def constant_assignment_node?(node)
          CONSTANT_ASSIGNMENT_CLASSES.any? { |node_class| node.is_a?(node_class) }
        end

        def record_top_level_constant(node)
          return unless class_stack.empty?

          name = node.respond_to?(:target) ? ConstantName.call(node.target) : node.name.to_s
          signature[:constants] << name unless name.nil?
        end
      end
      # rubocop:enable Metrics/ClassLength
      private_constant :SignatureVisitor
    end
  end
end
