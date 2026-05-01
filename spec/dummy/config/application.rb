# frozen_string_literal: true

require_relative "boot"

require "rails/all"

Bundler.require(*Rails.groups)

require "ruby_sage"

module Dummy
  class Application < Rails::Application
    config.load_defaults 7.0

    config.eager_load = false
    config.generators.system_tests = nil
  end
end
