# frozen_string_literal: true

require "ruby_sage/database_queries/safe_executor"

module RubySage
  module Tools
    # Lets the model run a read-only SELECT against the host's database. All
    # safety enforcement lives in {RubySage::DatabaseQueries::SafeExecutor};
    # this class only adapts the SafeExecutor result to the tool result shape.
    class DatabaseQuery < Base
      # @return [String]
      def self.name
        "query_database"
      end

      # @return [String]
      def self.description
        <<~TEXT.strip
          Run a single read-only SQL SELECT against the host application's database.
          Returns up to 100 rows. Supports standard ANSI SQL (table joins, WHERE,
          GROUP BY, ORDER BY, LIMIT). UPDATE/INSERT/DELETE/DDL are rejected.
          If you need to know what tables or columns exist, call describe_table first.
        TEXT
      end

      # @return [Hash]
      def self.input_schema
        {
          "type" => "object",
          "properties" => {
            "sql" => { "type" => "string", "description" => "A single SELECT statement." }
          },
          "required" => %w[sql]
        }
      end

      # @param executor [RubySage::DatabaseQueries::SafeExecutor]
      # @return [RubySage::Tools::DatabaseQuery]
      def initialize(executor: DatabaseQueries::SafeExecutor.new)
        super()
        @executor = executor
      end

      # @param input [Hash] expects +"sql"+.
      # @return [Hash]
      def call(input:)
        sql = input.is_a?(Hash) ? (input["sql"] || input[:sql]) : nil
        return tool_error("Missing required parameter: sql") if sql.to_s.strip.empty?

        @executor.call(sql: sql)
      rescue DatabaseQueries::SafeExecutor::UnsafeQuery => e
        tool_error("Query rejected: #{e.message}")
      end

      private

      def tool_error(message)
        { error: "tool_input_error", message: message }
      end
    end
  end
end
