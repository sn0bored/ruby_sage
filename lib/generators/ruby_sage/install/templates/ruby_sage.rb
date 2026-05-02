# frozen_string_literal: true

# RubySage configuration. See https://github.com/sn0bored/ruby_sage for full docs.

RubySage.configure do |config|
  # === Provider ===
  # :anthropic uses prompt caching from day 1 (recommended).
  # :openai works too; no caching in V1.
  config.provider            = :anthropic
  config.api_key             = ENV.fetch("ANTHROPIC_API_KEY", nil)
  config.model               = "claude-sonnet-4-6"
  config.summarization_model = "claude-haiku-4-5"

  # === Authorization ===
  # The default :admin scope requires you to provide an auth_check lambda
  # that returns true for users who are allowed to use RubySage.
  # config.scope      = :admin
  # config.auth_check = ->(controller) { controller.current_user&.admin? }
  #
  # Other scopes:
  # config.scope = :signed_in              # any signed-in user
  # config.scope = :public_rate_limited    # anyone (rate-limit at the host app level)

  # === CSP nonce (optional) ===
  # If your host app uses Content-Security-Policy with nonces, supply the
  # nonce so RubySage can attach it to the widget's <script> tag.
  # config.csp_nonce = ->(controller) { controller.content_security_policy_nonce }

  # === Mode ===
  # Shapes the system prompt AND filters which artifacts are visible to the
  # widget. Three audiences:
  #   :developer — code/architecture answers with file paths and class names
  #   :admin     — feature and workflow answers (no internals leaked)
  #   :user      — end-user how-to only; refuses to discuss internals
  # config.mode = :developer

  # === Audience scoping (controls which artifacts are visible per mode) ===
  # By default a heuristic tags each scanned file: services/jobs/policies are
  # developer-only, models/controllers/views are developer+admin, and the
  # :user audience is empty until you opt in.
  #
  # The simplest way to expose end-user help docs to :user mode:
  # config.user_facing_paths = ["app/views/help/**/*", "app/views/marketing/**/*"]
  #
  # For full control, supply a callable that returns an array of audience
  # symbols for each artifact. nil means "use the default heuristic."
  # config.audience_for = ->(attrs) {
  #   case attrs[:path]
  #   when /\Aapp\/views\/public\// then %i[developer admin user]
  #   when /\Aapp\/services\/billing\// then %i[developer]   # tighter than default
  #   end
  # }

  # === Scan retention ===
  # Keep the N most recent scans in the database; older ones are pruned.
  # config.scan_retention = 7

  # === Network timeouts ===
  # config.request_timeout = 30
  # config.max_retries     = 2
end
