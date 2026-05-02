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
    attr_accessor :provider, :api_key, :model, :summarization_model,
                  :auth_check, :scope, :mode, :scan_retention,
                  :scanner_include, :scanner_exclude,
                  :csp_nonce, :request_timeout, :max_retries,
                  :audience_for, :user_facing_paths

    # Builds a configuration object with conservative defaults.
    #
    # @return [RubySage::Configuration]
    def initialize
      @provider = :anthropic
      @model = "claude-sonnet-4-6"
      @summarization_model = "claude-haiku-4-5"
      @scope = :admin
      @mode = :developer
      @scan_retention = 7
      @scanner_include = default_scanner_include
      @scanner_exclude = default_scanner_exclude
      @request_timeout = 30
      @max_retries = 2
      @audience_for = nil
      @user_facing_paths = []
    end

    private

    def default_scanner_include
      DEFAULT_SCANNER_INCLUDE.dup
    end

    def default_scanner_exclude
      DEFAULT_SCANNER_EXCLUDE.dup
    end
  end
end
