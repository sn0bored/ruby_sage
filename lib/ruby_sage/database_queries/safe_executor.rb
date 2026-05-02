# frozen_string_literal: true

module RubySage
  module DatabaseQueries
    # Executes a SQL string in a way that is hard to misuse: SELECT-only,
    # single-statement, length-bounded, wrapped in a transaction that always
    # rolls back, and (on PostgreSQL) bounded by a statement timeout.
    #
    # Returns a structured hash describing rows, columns, and truncation —
    # never raises on a query that simply fails. Raises +UnsafeQuery+ when
    # validation rejects the SQL before execution.
    class SafeExecutor
      # Raised when SQL fails validation (non-SELECT, multi-statement, etc.).
      class UnsafeQuery < StandardError; end

      DEFAULT_MAX_ROWS = 100
      DEFAULT_TIMEOUT_MS = 5_000
      DEFAULT_MAX_CELL_BYTES = 1_024
      DEFAULT_MAX_SQL_LENGTH = 4_000

      LEADING_COMMENT_PATTERN = %r{\A(?:\s|--[^\n]*\n|/\*.*?\*/)+}m.freeze
      private_constant :LEADING_COMMENT_PATTERN

      LIMIT_PATTERN = /\bLIMIT\s+\d+/i.freeze
      private_constant :LIMIT_PATTERN

      # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter]
      # @param max_rows [Integer] hard cap on rows returned.
      # @param timeout_ms [Integer] statement timeout in milliseconds (PostgreSQL only).
      # @param max_cell_bytes [Integer] truncation threshold for individual string cells.
      # @param max_sql_length [Integer] reject SQL longer than this.
      # @return [RubySage::DatabaseQueries::SafeExecutor]
      def initialize(connection: ActiveRecord::Base.connection,
                     max_rows: DEFAULT_MAX_ROWS,
                     timeout_ms: DEFAULT_TIMEOUT_MS,
                     max_cell_bytes: DEFAULT_MAX_CELL_BYTES,
                     max_sql_length: DEFAULT_MAX_SQL_LENGTH)
        @connection = connection
        @max_rows = max_rows
        @timeout_ms = timeout_ms
        @max_cell_bytes = max_cell_bytes
        @max_sql_length = max_sql_length
      end

      # Validates and executes a SELECT.
      #
      # @param sql [String]
      # @return [Hash] one of:
      #   - +{ columns:, rows:, row_count:, truncated:, executed_sql: }+ on success
      #   - +{ error:, message:, executed_sql: }+ on a runtime DB error
      # @raise [UnsafeQuery] when validation rejects the SQL.
      def call(sql:)
        validate!(sql)
        bounded = enforce_limit(sql)
        execute(bounded)
      end

      private

      attr_reader :connection, :max_rows, :timeout_ms, :max_cell_bytes, :max_sql_length

      def validate!(sql)
        text = sql.to_s
        raise UnsafeQuery, "SQL is empty" if text.strip.empty?
        raise UnsafeQuery, "SQL exceeds #{max_sql_length} chars" if text.length > max_sql_length

        body = text.sub(LEADING_COMMENT_PATTERN, "")
        first_keyword = body.split(/\s+/).first.to_s.upcase
        unless first_keyword == "SELECT"
          raise UnsafeQuery,
                "Only SELECT queries are allowed (got #{first_keyword.inspect})"
        end
        raise UnsafeQuery, "Multi-statement queries are not allowed" if multi_statement?(text)
      end

      def multi_statement?(sql)
        without_strings = sql.gsub(/'(?:[^']|'')*'/, "''").gsub(/"(?:[^"]|"")*"/, '""')
        stripped = without_strings.gsub(/--[^\n]*\n/, "").gsub(%r{/\*.*?\*/}m, "")
        stripped.sub(/;\s*\z/, "").include?(";")
      end

      def enforce_limit(sql)
        cleaned = sql.strip.chomp(";")
        return cleaned if cleaned.match?(LIMIT_PATTERN)

        "#{cleaned} LIMIT #{max_rows}"
      end

      def execute(sql)
        result = run_in_transaction(sql)
        format_success(sql, result)
      rescue ActiveRecord::StatementInvalid => e
        { error: "query_failed", message: e.message, executed_sql: sql }
      end

      def run_in_transaction(sql)
        result = nil
        connection.transaction(requires_new: true) do
          apply_statement_timeout
          result = connection.exec_query(sql)
          raise ActiveRecord::Rollback
        end
        result
      end

      def apply_statement_timeout
        return unless connection.adapter_name.to_s.match?(/PostgreSQL/i)

        connection.execute("SET LOCAL statement_timeout = #{timeout_ms.to_i}")
      end

      def format_success(sql, result)
        capped_rows = Array(result.rows).first(max_rows).map { |row| row.map { |value| truncate_cell(value) } }
        {
          columns: Array(result.columns),
          rows: capped_rows,
          row_count: capped_rows.size,
          truncated: Array(result.rows).size > capped_rows.size,
          executed_sql: sql
        }
      end

      def truncate_cell(value)
        return value unless value.is_a?(String) && value.bytesize > max_cell_bytes

        "#{value.byteslice(0, max_cell_bytes)}…"
      end
    end
  end
end
