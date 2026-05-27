# frozen_string_literal: true

require "ruby_sage/mcp/tools/base"

module RubySage
  module MCP
    module Tools
      # Finds likely relevant files from disk artifacts and routes.
      class FindRelevantFiles < Base
        NAME = "find_relevant_files"
        DESCRIPTION = "Find files relevant to a query using RubySage disk artifacts."
        DEFAULT_MAX_RESULTS = 20
        INPUT_SCHEMA = {
          "type" => "object",
          "properties" => {
            "query" => {
              "type" => "string",
              "description" => "Natural-language query, symbol name, or route path."
            },
            "max_results" => {
              "type" => "number",
              "description" => "Maximum number of file matches to return."
            }
          },
          "required" => ["query"],
          "additionalProperties" => false
        }.freeze

        # @param arguments [Hash] tool arguments.
        # @return [Array<Hash>] ranked file matches with reasons.
        def call(arguments)
          query = require_string(arguments, "query")
          max_results = integer_argument(arguments, "max_results", DEFAULT_MAX_RESULTS)
          artifacts = disk_store.each_artifact.to_a
          hits = artifact_hits(artifacts, query)
          merge_route_hits(hits, artifacts, query)
          ranked_hits(hits, max_results)
        end

        private

        def artifact_hits(artifacts, query)
          artifacts.each_with_object({}) do |payload, hits|
            hit = base_hit(payload)
            score_symbols(hit, payload, query)
            score_artifact_text(hit, payload, query)
            hits[hit["path"]] = hit if hit["_score"].positive?
          end
        end

        def base_hit(payload)
          {
            "path" => value_for(payload, :path),
            "kind" => value_for(payload, :kind),
            "reasons" => [],
            "_score" => 0
          }
        end

        def score_symbols(hit, payload, query)
          (signature_classes(payload) + signature_methods(payload)).each do |entry|
            name = value_for(entry, :name)
            next unless matches_query?(name, query)

            add_score(hit, 10, "symbol:#{name}")
          end
        end

        def score_artifact_text(hit, payload, query)
          add_score(hit, 2, "summary") if text_matches_query?(value_for(payload, :summary), query)
          Array(value_for(payload, :public_symbols)).each do |symbol|
            add_score(hit, 2, "public_symbol:#{symbol}") if matches_query?(symbol, query)
          end
          add_score(hit, 1, "path:#{hit['path']}") if matches_query?(hit["path"], query)
          score_route_mappings(hit, payload, query)
        end

        def score_route_mappings(hit, payload, query)
          Array(value_for(payload, :route_mappings)).each do |mapping|
            add_score(hit, 8, "route:#{route_reason(mapping)}") if text_matches_query?(mapping, query)
          end
        end

        def merge_route_hits(hits, artifacts, query)
          read_routes.each do |route|
            next unless route_matches_query?(route, query)

            file = value_for(route, "file")
            next if file.nil?

            hit = hits[file] || route_hit(file, artifacts)
            add_score(hit, 8, "route:#{value_for(route, 'path')}")
            hits[file] = hit
          end
        end

        def route_hit(file, artifacts)
          payload = artifacts.find { |artifact| value_for(artifact, :path) == file } || {}
          {
            "path" => file,
            "kind" => value_for(payload, :kind) || "controller",
            "reasons" => [],
            "_score" => 0
          }
        end

        def route_matches_query?(route, query)
          path = value_for(route, "path")
          return false if path.nil?

          text_matches_query?(path, query)
        end

        def route_reason(mapping)
          mapping.to_s.split(/\s+/).find { |part| part.start_with?("/") } || mapping.to_s
        end

        def ranked_hits(hits, max_results)
          hits.values
              .sort_by { |hit| [-hit["_score"], hit["path"].to_s] }
              .first([max_results, 0].max)
              .map { |hit| public_hit(hit) }
        end

        def public_hit(hit)
          {
            "path" => hit["path"],
            "kind" => hit["kind"],
            "reasons" => hit["reasons"]
          }
        end

        def add_score(hit, score, reason)
          hit["_score"] += score
          hit["reasons"] << reason unless hit["reasons"].include?(reason)
        end

        def matches_query?(value, query)
          return false if value.nil?

          normalized_value = value.to_s.downcase
          normalized_query = query.to_s.downcase
          normalized_query.include?(normalized_value) ||
            normalized_value.include?(normalized_query) ||
            query_terms(normalized_query).any? { |term| normalized_value.include?(term) }
        end

        def text_matches_query?(value, query)
          return false if value.nil?

          normalized_value = value.to_s.downcase
          normalized_query = query.to_s.downcase
          normalized_value.include?(normalized_query) ||
            query_terms(normalized_query).any? { |term| normalized_value.include?(term) }
        end

        def query_terms(query)
          query.scan(/[a-z0-9_?!]+/).select { |term| term.length >= 3 }
        end
      end
    end
  end
end
