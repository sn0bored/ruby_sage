# frozen_string_literal: true

require "json"
require "rails/generators/base"
require "rails/generators/migration"
require "ruby_sage/artifacts/disk_store"

module RubySage
  module Generators
    # Installs RubySage into a host Rails application.
    #
    # @example Run from a host app
    #   rails generate ruby_sage:install --with-claude-config
    class InstallGenerator < ::Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Install RubySage into a Rails application."

      class_option :with_claude_config,
                   type: :boolean,
                   default: false,
                   desc: "Also write a .claude.json snippet for the MCP server."

      # Copies the host application initializer.
      #
      # @return [void]
      def copy_initializer
        template "ruby_sage.rb", "config/initializers/ruby_sage.rb"
      end

      # Copies RubySage engine migrations into the host application.
      #
      # @return [void]
      def install_migrations
        rake "ruby_sage:install:migrations"
      end

      # Creates the disk-backed artifact layout used by the scanner and MCP server.
      #
      # @return [void]
      def create_disk_layout
        in_root do
          empty_directory ".ruby_sage"
          RubySage::Artifacts::DiskStore.new(host_root: destination_root).ensure_layout
        end
      end

      # Runs the initial scan when the RubySage database tables already exist.
      #
      # Fresh installs still need the host app to run +db:migrate+ first, so in
      # that case the generated next steps print the scan command instead.
      #
      # @return [void]
      def run_initial_scan
        if ruby_sage_tables_exist?
          rake "ruby_sage:scan"
        else
          say_status "skip", "ruby_sage:scan until after db:migrate", :yellow
        end
      end

      # Writes or merges the Claude Code MCP configuration snippet.
      #
      # @return [void]
      def write_claude_config
        return unless options[:with_claude_config]

        in_root do
          path = File.join(destination_root, ".claude.json")
          action = File.file?(path) ? "update" : "create"
          config = read_claude_config(path)
          config["mcpServers"] = merged_mcp_servers(config["mcpServers"])
          File.write(path, "#{JSON.pretty_generate(config)}\n")
          say_status action, ".claude.json"
        end
      end

      # Prints host-app setup instructions.
      #
      # @return [void]
      def print_next_steps
        say <<~TEXT

          RubySage installed.

          Next steps:
            1. Add an :anthropic API key to config/initializers/ruby_sage.rb or .env
            2. bin/rails db:migrate
            3. bundle exec rake ruby_sage:scan    # writes .ruby_sage/
            4. Mount widget routes:   <%= ruby_sage_widget %> in your layout
            5. Start your dev server. The widget appears bottom-right.

          The MCP server can be invoked with:
            bundle exec ruby_sage mcp --host-root .

          For Claude Code, see .claude.json (created with --with-claude-config) or
          copy from README "Claude Code integration".
        TEXT
      end

      # Returns the next Rails migration timestamp.
      #
      # @param dirname [String] migration directory.
      # @return [String]
      def self.next_migration_number(dirname)
        if ActiveRecord::Base.timestamped_migrations
          Time.now.utc.strftime("%Y%m%d%H%M%S")
        else
          format("%.3d", current_migration_number(dirname) + 1)
        end
      end

      private

      def ruby_sage_tables_exist?
        return false unless defined?(ActiveRecord::Base)

        connection = ActiveRecord::Base.connection
        connection.data_source_exists?("ruby_sage_scans") &&
          connection.data_source_exists?("ruby_sage_artifacts")
      rescue StandardError
        false
      end

      def read_claude_config(path)
        return {} unless File.file?(path)

        config = JSON.parse(File.read(path))
        return config if config.is_a?(Hash)

        raise Thor::Error, ".claude.json must contain a JSON object"
      rescue JSON::ParserError => e
        raise Thor::Error, "Could not parse .claude.json: #{e.message}"
      end

      def merged_mcp_servers(existing_servers)
        servers = existing_servers.is_a?(Hash) ? existing_servers : {}
        servers.merge("ruby_sage" => ruby_sage_mcp_server)
      end

      def ruby_sage_mcp_server
        {
          "command" => "bundle",
          "args" => ["exec", "ruby_sage", "mcp", "--host-root", "."]
        }
      end
    end
  end
end
