# frozen_string_literal: true

require "active_support/core_ext/string/inflections"
require "fileutils"
require "json"
require "pathname"

module RubySage
  module Extractors
    # Writes a static route map for the loaded Rails application.
    class RoutesLoader
      SCHEMA_VERSION = 1
      ROUTES_FILENAME = "routes.json"
      INTERNAL_CONTROLLER_PREFIXES = %w[
        action_mailbox/
        active_storage/
        rails/
        ruby_sage/
      ].freeze

      # @param host_root [String, Pathname] root of the loaded Rails app.
      # @return [RubySage::Extractors::RoutesLoader]
      def initialize(host_root:)
        @host_root = Pathname(host_root).expand_path
      end

      # Writes `.ruby_sage/routes.json` when Rails routes are available.
      #
      # @return [Pathname, nil] written path, or nil when no Rails app matches.
      def run
        return nil unless rails_application_available?

        FileUtils.mkdir_p(routes_path.dirname)
        File.write(routes_path, "#{JSON.pretty_generate(payload)}\n")
        routes_path
      rescue NameError
        nil
      end

      private

      attr_reader :host_root

      def rails_application_available?
        defined?(Rails) &&
          Rails.respond_to?(:application) &&
          Rails.application.respond_to?(:routes) &&
          Pathname(Rails.root).expand_path == host_root
      end

      def payload
        {
          schema_version: SCHEMA_VERSION,
          routes: routes
        }
      end

      def routes
        Rails.application.routes.routes.filter_map do |route|
          route_entry(route) unless internal_route?(route)
        end
      end

      def route_entry(route)
        defaults = route.defaults
        controller_path = defaults[:controller]
        action = defaults[:action]
        return nil if controller_path.nil? || action.nil?

        controller_name = controller_class_name(controller_path)
        {
          verb: normalize_verb(route.verb),
          path: normalize_path(route.path.spec.to_s),
          controller: controller_name,
          action: action.to_s,
          file: controller_file(controller_name),
          name: route.name&.to_s
        }
      end

      def internal_route?(route)
        defaults = route.defaults
        controller_path = defaults[:controller].to_s
        return true if controller_path.empty?

        INTERNAL_CONTROLLER_PREFIXES.any? { |prefix| controller_path.start_with?(prefix) }
      end

      def controller_class_name(controller_path)
        candidate = "#{controller_path.camelize}Controller"
        controller_class = candidate.safe_constantize
        controller_class ? controller_class.name : candidate
      end

      def controller_file(controller_name)
        relative = "app/controllers/#{controller_name.underscore}.rb"
        host_root.join(relative).file? ? relative : nil
      end

      def normalize_verb(verb)
        verb.to_s.sub(/\A\^/, "").sub(/\$\z/, "").sub(/\A\(\?-mix:(.*)\)\z/, "\\1")
      end

      def normalize_path(path)
        normalized = path.sub(/\(\.:format\)\z/, "")
        normalized.empty? ? "/" : normalized
      end

      def routes_path
        host_root.join(".ruby_sage", ROUTES_FILENAME)
      end
    end
  end
end
