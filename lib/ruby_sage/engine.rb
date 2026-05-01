# frozen_string_literal: true

require "rails/engine"

module RubySage
  class Engine < ::Rails::Engine
    isolate_namespace RubySage

    # Registers engine migrations with the host app so RubySage tables are
    # created by the host application's normal `rails db:migrate` workflow.
    initializer :append_migrations do |app|
      unless app.root.to_s == root.to_s
        config.paths["db/migrate"].expanded.each do |path|
          app.config.paths["db/migrate"] << path
        end
      end
    end

    initializer "ruby_sage.assets" do |app|
      assets_config = app.config.assets if app.config.respond_to?(:assets)

      assets_config.precompile += %w[ruby_sage_manifest.js] if assets_config.respond_to?(:precompile)
    end
  end
end
