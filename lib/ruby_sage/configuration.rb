# frozen_string_literal: true

module RubySage
  # Runtime configuration for the RubySage engine.
  class Configuration
    DEFAULT_SCANNER_INCLUDE = [
      "app/models",
      "app/controllers",
      "app/services",
      "app/jobs",
      "app/mailers",
      "app/policies",
      "app/queries",
      "app/serializers",
      "app/decorators",
      "app/helpers",
      "app/components",
      "app/workers",
      "app/views",
      "config/routes.rb",
      "db/schema.rb",
      "README.md",
      "CLAUDE.md",
      ".cursorrules"
    ].freeze
    private_constant :DEFAULT_SCANNER_INCLUDE

    DEFAULT_SCANNER_EXCLUDE = [
      "vendor/",
      "node_modules/",
      "tmp/",
      "log/",
      "db/seeds.rb",
      "db/data/",
      "config/credentials*",
      "*.env*",
      "*.key",
      "*.pem"
    ].freeze
    private_constant :DEFAULT_SCANNER_EXCLUDE

    # @!attribute [rw] provider
    #   @return [Symbol] provider adapter key.
    # @!attribute [rw] api_key
    #   @return [String, nil] API key supplied by the host app.
    # @!attribute [rw] model
    #   @return [String] provider model for chat responses.
    # @!attribute [rw] summarization_model
    #   @return [String] provider model for scan-time summaries.
    # @!attribute [rw] auth_check
    #   @return [Proc, nil] callable receiving the controller instance.
    # @!attribute [rw] scope
    #   @return [Symbol] authorization fallback scope.
    # @!attribute [rw] mode
    #   @return [Symbol] widget persona: +:developer+, +:admin+, or +:user+.
    #     Controls the system prompt and starter questions shown in the widget.
    # @!attribute [rw] scan_retention
    #   @return [Integer] number of scans to retain.
    # @!attribute [rw] scanner_include
    #   @return [Array<String>] host paths included by the scanner.
    # @!attribute [rw] scanner_exclude
    #   @return [Array<String>] host paths and globs excluded by the scanner.
    # @!attribute [rw] csp_nonce
    #   @return [Proc, nil] callable used by helpers to resolve a CSP nonce.
    # @!attribute [rw] request_timeout
    #   @return [Integer] provider request timeout in seconds.
    # @!attribute [rw] max_retries
    #   @return [Integer] maximum provider retry attempts.
    # @!attribute [rw] audience_for
    #   @return [Proc, nil] callable receiving an artifact attributes hash and
    #     returning an array of audience symbols (+:developer+, +:admin+,
    #     +:user+). Overrides the default heuristic in +AudienceClassifier+.
    # @!attribute [rw] user_facing_paths
    #   @return [Array<String>] glob patterns whose matching files are
    #     additionally tagged for the +:user+ audience. Use this to expose
    #     end-user help docs without writing a custom +audience_for+ callable.
    # @!attribute [rw] enable_database_queries
    #   @return [Boolean] when true and +mode+ is +:admin+, the chat loop can
    #     run read-only SELECT queries against the host database via the
    #     +query_database+ + +describe_table+ tools. Default false.
    # @!attribute [rw] query_scope
    #   @return [Proc, nil] callable receiving the request controller and
    #     returning a SQL fragment ("organization_id = 42"). Appended to the
    #     +:admin+ system prompt to remind the model to scope its queries.
    #     V1 is prompt-level guidance; for hard tenant isolation, configure
    #     +query_connection+ with row-level security.
    # @!attribute [rw] query_connection
    #   @return [Proc, nil] callable returning the ActiveRecord connection the
    #     query tool should use. Use this to point at a read-only database
    #     user. Defaults to +ActiveRecord::Base.connection+.
    # @!attribute [rw] max_query_rows
    #   @return [Integer] hard cap on rows returned per query. Default 100.
    # @!attribute [rw] query_timeout_ms
    #   @return [Integer] PostgreSQL statement_timeout per query. Default 5000.
    # @!attribute [rw] tool_loop_max_iterations
    #   @return [Integer] safety cap on tool-call iterations per chat turn.
    #     Default 5.
    attr_accessor :provider, :api_key, :model, :summarization_model,
                  :auth_check, :scope, :mode, :scan_retention,
                  :scanner_include, :scanner_exclude,
                  :csp_nonce, :request_timeout, :max_retries,
                  :audience_for, :user_facing_paths,
                  :enable_database_queries, :query_scope, :query_connection,
                  :max_query_rows, :query_timeout_ms, :tool_loop_max_iterations

    # Builds a configuration object with conservative defaults.
    #
    # @return [RubySage::Configuration]
    def initialize
      assign_provider_defaults
      assign_scanner_defaults
      assign_audience_defaults
      assign_database_query_defaults
    end

    private

    def assign_provider_defaults
      @provider = :anthropic
      @model = "claude-sonnet-4-6"
      @summarization_model = "claude-haiku-4-5"
      @request_timeout = 30
      @max_retries = 2
    end

    def assign_scanner_defaults
      @scope = :admin
      @mode = :developer
      @scan_retention = 7
      @scanner_include = default_scanner_include
      @scanner_exclude = default_scanner_exclude
    end

    def assign_audience_defaults
      @audience_for = nil
      @user_facing_paths = []
    end

    def assign_database_query_defaults
      @enable_database_queries = false
      @query_scope = nil
      @query_connection = nil
      @max_query_rows = 100
      @query_timeout_ms = 5_000
      @tool_loop_max_iterations = 5
    end

    def default_scanner_include
      DEFAULT_SCANNER_INCLUDE.dup
    end

    def default_scanner_exclude
      DEFAULT_SCANNER_EXCLUDE.dup
    end
  end
end
