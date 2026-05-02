# frozen_string_literal: true

module RubySage
  # Runs a series of checks against a host application's RubySage install and
  # reports actionable findings. Backs the +rake ruby_sage:doctor+ task.
  #
  # Each check returns a +Finding+ struct: +:status+ is +:ok+, +:warn+, or
  # +:error+; +:message+ describes what was checked; +:fix+ (optional) gives
  # the user something concrete to do.
  class Doctor
    SEVERITY_LABELS = { ok: "✓", warn: "!", error: "✗" }.freeze

    Finding = Struct.new(:check, :status, :message, :fix, keyword_init: true) do
      def ok?
        status == :ok
      end

      def severity_label
        RubySage::Doctor::SEVERITY_LABELS[status]
      end
    end

    CHECKS = %i[
      check_provider_configured
      check_api_key_present
      check_auth_check_configured
      check_completed_scan_exists
      check_recent_scan
      check_artifact_audience_coverage
      check_user_mode_safety
      check_database_queries_safety
      check_chat_turn_persistence
    ].freeze

    # @param config [RubySage::Configuration]
    # @return [RubySage::Doctor]
    def initialize(config: RubySage.configuration)
      @config = config
    end

    # Runs every check and returns the findings array.
    #
    # @return [Array<Finding>]
    def run
      CHECKS.map { |check| send(check) }
    end

    private

    attr_reader :config

    def check_provider_configured
      either("provider", "Provider is :#{config.provider}", config.provider.is_a?(Symbol))
    end

    def check_api_key_present
      return ok_finding("api_key", "Provider API key configured") if config.api_key.to_s.length.positive?

      warn_finding(
        "api_key",
        "Provider API key not configured.",
        "Either set ENV['ANTHROPIC_API_KEY'] (or OPENAI_API_KEY) " \
        "or use the agent-driven scan flow (`rake ruby_sage:scan:plan`)."
      )
    end

    def check_auth_check_configured
      return ok_finding("auth_check", "auth_check callable configured") if config.auth_check.respond_to?(:call)

      error_finding(
        "auth_check",
        "auth_check is not configured. Every chat request will be denied.",
        "Set `config.auth_check = ->(controller) { controller.current_user&.admin? }` " \
        "in config/initializers/ruby_sage.rb"
      )
    end

    def check_completed_scan_exists
      count = Scan.where(status: "completed").count
      return ok_finding("scans", "#{count} completed scan(s) on file") if count.positive?

      error_finding(
        "scans",
        "No completed scans yet. The chat widget will return zero artifacts.",
        "Run `bundle exec rake ruby_sage:scan` (API path) or " \
        "`bundle exec rake ruby_sage:scan:plan` (free agent-driven path)."
      )
    end

    def check_recent_scan
      latest = Scan.where(status: "completed").order(finished_at: :desc).first
      return ok_finding("scan_freshness", "No scans yet") if latest.nil?

      age_days = ((Time.current - latest.finished_at) / 86_400).to_i
      return ok_finding("scan_freshness", "Latest scan is #{age_days}d old") if age_days <= 7

      warn_finding(
        "scan_freshness",
        "Latest scan is #{age_days} days old — answers may reference outdated code.",
        "Run a fresh scan or set up a daily cron."
      )
    end

    def check_artifact_audience_coverage
      latest = Scan.where(status: "completed").order(finished_at: :desc).first
      return ok_finding("audiences", "No scans to check") if latest.nil?

      total = latest.artifacts.count
      tagged = latest.artifacts.reject { |a| Array(a.audiences).empty? }.count
      missing = total - tagged
      return ok_finding("audiences", "All #{total} artifacts have audience tags") if missing.zero?

      warn_finding(
        "audiences",
        "#{missing} of #{total} artifacts have no audience tags (visible to every mode).",
        "Re-run a scan to apply current audience heuristics."
      )
    end

    def check_user_mode_safety
      return ok_finding("user_mode", "Mode is :#{config.mode}, no extra check needed") unless config.mode == :user

      latest = Scan.where(status: "completed").order(finished_at: :desc).first
      return warn_finding("user_mode", "Mode is :user but no scan exists yet") if latest.nil?

      visible = latest.artifacts.count { |a| a.visible_in_mode?(:user) }
      if visible.zero?
        return warn_finding(
          "user_mode",
          "Mode is :user but 0 artifacts are :user-visible — chat will return empty results.",
          "Set `config.user_facing_paths = [\"app/views/help/**/*\"]` to expose end-user content."
        )
      end

      ok_finding("user_mode", "Mode is :user with #{visible} :user-visible artifacts")
    end

    def check_database_queries_safety
      return ok_finding("db_queries", "Database queries disabled (default)") unless config.enable_database_queries

      if config.mode != :admin
        warn_finding("db_queries", "enable_database_queries on but mode is :#{config.mode} (only :admin uses tools)")
      elsif config.query_connection.nil?
        warn_finding("db_queries", "enable_database_queries is on but no query_connection is set.",
                     "For hard tenant isolation, set `config.query_connection = ->(c) { ReadOnlyDB.connection }`.")
      else
        ok_finding("db_queries", "Database queries enabled with read-only connection")
      end
    end

    def check_chat_turn_persistence
      return ok_finding("chat_turns", "Chat turn persistence disabled") unless config.persist_chat_turns
      return ok_finding("chat_turns", "Chat turn persistence enabled") if defined?(ChatTurn) && ChatTurn.table_exists?

      error_finding(
        "chat_turns",
        "persist_chat_turns is on but the ruby_sage_chat_turns table is missing.",
        "Run `bundle exec rails ruby_sage:install:migrations && rails db:migrate`."
      )
    end

    def either(check, message, condition)
      condition ? ok_finding(check, message) : error_finding(check, message)
    end

    def ok_finding(check, message, fix = nil)
      Finding.new(check: check, status: :ok, message: message, fix: fix)
    end

    def warn_finding(check, message, fix = nil)
      Finding.new(check: check, status: :warn, message: message, fix: fix)
    end

    def error_finding(check, message, fix = nil)
      Finding.new(check: check, status: :error, message: message, fix: fix)
    end
  end
end
