# frozen_string_literal: true

Rails.application.configure do
  config.cache_classes = true
  config.eager_load = ENV["CI"].present?
  config.public_file_server.enabled = true
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false
  config.action_controller.allow_forgery_protection = false
  config.cache_store = :null_store
  config.action_mailer.delivery_method = :test
  config.active_support.deprecation = :stderr
  config.active_support.disallowed_deprecation = :raise
  config.active_support.disallowed_deprecation_warnings = []
end

RubySage.configure do |config|
  config.scope = :public_rate_limited
end
