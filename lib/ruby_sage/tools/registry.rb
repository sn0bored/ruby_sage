# frozen_string_literal: true

module RubySage
  module Tools
    # Holds the active set of tools for one chat request. The chat loop asks
    # the registry for provider-shaped tool definitions and dispatches
    # +tool_use+ blocks back to the matching tool instance's +call+ method.
    class Registry
      # @return [RubySage::Tools::Registry]
      def self.empty
        new(tools: [])
      end

      # Returns a registry populated with the default tools for the given mode
      # and configuration. +:admin+ mode with +config.enable_database_queries+
      # gets +DatabaseQuery+ + +DescribeTable+; every other combination is
      # empty. When +config.query_connection+ is a callable, it is invoked
      # with +controller+ and the returned connection is wired into both
      # tools. Falls back to +ActiveRecord::Base.connection+ otherwise.
      #
      # @param mode [Symbol]
      # @param config [RubySage::Configuration]
      # @param controller [ActionController::Base, nil]
      # @return [RubySage::Tools::Registry]
      def self.for(mode:, config: RubySage.configuration, controller: nil)
        return empty unless mode.to_sym == :admin && config.enable_database_queries

        connection = resolve_connection(config, controller)
        executor = DatabaseQueries::SafeExecutor.new(
          connection: connection,
          max_rows: config.max_query_rows,
          timeout_ms: config.query_timeout_ms
        )
        new(tools: [DatabaseQuery.new(executor: executor), DescribeTable.new(connection: connection)])
      end

      def self.resolve_connection(config, controller)
        callable = config.query_connection
        return ActiveRecord::Base.connection if callable.nil?

        callable.call(controller)
      end
      private_class_method :resolve_connection

      # @param tools [Array<RubySage::Tools::Base>]
      # @return [RubySage::Tools::Registry]
      def initialize(tools:)
        @tools = tools
      end

      # @return [Boolean]
      delegate :empty?, to: :@tools

      # Tool definitions ready to send to Anthropic.
      #
      # @return [Array<Hash>]
      def to_anthropic
        @tools.map { |tool| tool.class.to_anthropic }
      end

      # Dispatches one tool_use block to the matching tool.
      #
      # @param name [String]
      # @param input [Hash]
      # @return [Hash] tool's return value, or +tool_not_found+ error.
      def dispatch(name:, input:)
        tool = @tools.find { |candidate| tool_name_for(candidate) == name }
        return { error: "tool_not_found", message: "No tool registered for #{name.inspect}" } if tool.nil?

        tool.call(input: input)
      end

      private

      def tool_name_for(tool_instance)
        tool_instance.class.name
      end
    end
  end
end
