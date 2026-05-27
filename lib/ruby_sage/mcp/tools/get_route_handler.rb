# frozen_string_literal: true

require "ruby_sage/mcp/tools/base"

module RubySage
  module MCP
    module Tools
      # Looks up a Rails route handler from the static routes.json artifact.
      class GetRouteHandler < Base
        NAME = "get_route_handler"
        DESCRIPTION = "Find the controller action and file handling a Rails route path."
        INPUT_SCHEMA = {
          "type" => "object",
          "properties" => {
            "path" => {
              "type" => "string",
              "description" => "URL path to resolve, such as /posts/1."
            },
            "verb" => {
              "type" => "string",
              "description" => "HTTP verb to match. Defaults to GET."
            }
          },
          "required" => ["path"],
          "additionalProperties" => false
        }.freeze

        # @param arguments [Hash] tool arguments.
        # @return [Hash, nil] matching route handler, or nil when no route matches.
        def call(arguments)
          path = normalize_path(require_string(arguments, "path"))
          verb = (value_for(arguments, "verb") || "GET").to_s.upcase
          route = read_routes.find { |candidate| route_matches?(candidate, path, verb) }
          route.nil? ? nil : route_result(route)
        end

        private

        def route_matches?(route, path, verb)
          verb_matches?(value_for(route, "verb"), verb) &&
            path_matches?(value_for(route, "path"), path)
        end

        def verb_matches?(route_verb, requested_verb)
          route_verb.to_s.split("|").include?(requested_verb)
        end

        def path_matches?(route_path, requested_path)
          return false if route_path.nil?
          return true if route_path == requested_path

          route_segments_match?(route_path.to_s.split("/"), requested_path.split("/"))
        end

        def route_segments_match?(route_segments, requested_segments)
          return false unless route_segments.length == requested_segments.length

          route_segments.zip(requested_segments).all? do |route_segment, requested_segment|
            route_segment == requested_segment ||
              route_segment.start_with?(":") ||
              route_segment.start_with?("*")
          end
        end

        def normalize_path(path)
          normalized = path.to_s.split("?").first
          normalized.start_with?("/") ? normalized : "/#{normalized}"
        end

        def route_result(route)
          {
            "verb" => value_for(route, "verb"),
            "path" => value_for(route, "path"),
            "controller" => value_for(route, "controller"),
            "action" => value_for(route, "action"),
            "file" => value_for(route, "file")
          }
        end
      end
    end
  end
end
