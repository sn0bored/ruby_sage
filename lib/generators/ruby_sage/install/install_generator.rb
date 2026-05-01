# frozen_string_literal: true

require "rails/generators/base"

module RubySage
  module Generators
    # Installs RubySage into a host Rails application: copies the configuration
    # initializer template into +config/initializers/ruby_sage.rb+ and copies
    # the engine's database migrations into the host's +db/migrate+ directory.
    #
    # @example Run from a host app
    #   $ rails generate ruby_sage:install
    class InstallGenerator < ::Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Install RubySage: configuration initializer + database migrations."

      # Copies the initializer template, exposing every documented configuration
      # key so the host app maintainer can find them in one place.
      #
      # @return [void]
      def copy_initializer
        template "ruby_sage.rb", "config/initializers/ruby_sage.rb"
      end

      # Pulls the engine migrations into the host app via Rails' built-in
      # +railties:install:migrations+ task.
      #
      # @return [void]
      def install_migrations
        rake "ruby_sage:install:migrations"
      end
    end
  end
end
