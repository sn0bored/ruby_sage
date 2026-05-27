# frozen_string_literal: true

# RubySage configuration.
# See https://github.com/sn0bored/ruby_sage for full docs.

RubySage.configure do |config|
  # RubySage defaults to Anthropic. Switch this if you configure another provider.
  # config.provider = :anthropic
  config.api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)

  # The default :admin scope calls this lambda before serving the widget or API.
  # Replace current_user/admin? with the host app's authorization rule.
  # config.auth_check = ->(controller) { controller.current_user&.admin? }
  config.auth_check = ->(controller) { controller.current_user&.admin? }

  # Default scanner include paths:
  # config.scanner_include = %w[
  #   app/models app/controllers app/services app/jobs app/mailers app/policies
  #   app/queries app/serializers app/decorators app/helpers app/components
  #   app/workers app/views config/routes.rb db/schema.rb README.md CLAUDE.md
  #   .cursorrules
  # ]

  # Default scanner exclude paths and globs:
  # config.scanner_exclude = [
  #   "vendor/",
  #   "node_modules/",
  #   "tmp/",
  #   "log/",
  #   "db/seeds.rb",
  #   "db/data/",
  #   "config/credentials*",
  #   "*.env*",
  #   "*.key",
  #   "*.pem"
  # ]
end
