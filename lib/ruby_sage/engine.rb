# frozen_string_literal: true

require "rails/engine"

module RubySage
  class Engine < ::Rails::Engine
    isolate_namespace RubySage

    initializer "ruby_sage.assets" do |app|
      assets_config = app.config.assets if app.config.respond_to?(:assets)

      assets_config.precompile += %w[ruby_sage_manifest.js] if assets_config.respond_to?(:precompile)
    end
  end
end
