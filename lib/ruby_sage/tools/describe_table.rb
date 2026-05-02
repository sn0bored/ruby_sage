# frozen_string_literal: true

module RubySage
  module Tools
    # Returns the column list (with types and nullability) for a database table,
    # so the model can write accurate SELECTs without guessing column names.
    class DescribeTable < Base
      # @return [String]
      def self.name
        "describe_table"
      end

      # @return [String]
      def self.description
        <<~TEXT.strip
          Return the column names, SQL types, and nullability for one database table.
          Call this before query_database when you are not sure what columns a table
          has. Returns an error if the table does not exist.
        TEXT
      end

      # @return [Hash]
      def self.input_schema
        {
          "type" => "object",
          "properties" => {
            "table_name" => { "type" => "string", "description" => "Exact table name." }
          },
          "required" => %w[table_name]
        }
      end

      # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter]
      # @return [RubySage::Tools::DescribeTable]
      def initialize(connection: ActiveRecord::Base.connection)
        super()
        @connection = connection
      end

      # @param input [Hash] expects +"table_name"+.
      # @return [Hash]
      def call(input:)
        table_name = input.is_a?(Hash) ? (input["table_name"] || input[:table_name]) : nil
        return tool_error("Missing required parameter: table_name") if table_name.to_s.strip.empty?
        return tool_error("Unknown table: #{table_name}") unless @connection.table_exists?(table_name)

        { table_name: table_name, columns: column_descriptions(table_name) }
      end

      private

      def column_descriptions(table_name)
        @connection.columns(table_name).map do |column|
          { name: column.name, sql_type: column.sql_type, null: column.null }
        end
      end

      def tool_error(message)
        { error: "tool_input_error", message: message }
      end
    end
  end
end
