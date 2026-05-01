# frozen_string_literal: true

require "set"
require "uri"

module RubySage
  # Given a natural-language query and optional page URL, retrieves the most
  # relevant artifacts from the latest completed scan, with citations.
  #
  # @example
  #   result = RubySage::Retriever.new.call(query: "how does donor matching work?")
  #   result[:artifacts]
  #   result[:citations]
  class Retriever
    DEFAULT_LIMIT = 10
    PAGE_CONTEXT_BOOST = 2.5

    STOPWORDS = Set.new(%w[a an the is are was were in on at to of for and or but that this it we our my your]).freeze
    private_constant :STOPWORDS

    # Initializes a retriever for a scan.
    #
    # @param scan [RubySage::Scan, nil] scan to retrieve from.
    # @param limit [Integer] maximum number of artifacts to return.
    # @return [RubySage::Retriever]
    def initialize(scan: Scan.latest_completed.first, limit: DEFAULT_LIMIT)
      @scan = scan
      @limit = limit
    end

    # Retrieves relevant artifacts and citations.
    #
    # @param query [String] natural-language question.
    # @param page_context [Hash, nil] optional page context with :url and :title.
    # @return [Hash] artifacts, citations, and scan id.
    def call(query:, page_context: nil)
      return { artifacts: [], citations: [], scan_id: nil } if @scan.nil?

      tokens = tokenize(query)
      route_artifact_ids = artifact_ids_for_route(page_context)
      top = score(tokens: tokens, route_artifact_ids: route_artifact_ids).first(@limit)

      {
        artifacts: top.map(&:first),
        citations: top.map { |artifact, artifact_score| citation_for(artifact, artifact_score) },
        scan_id: @scan.id
      }
    end

    private

    def tokenize(text)
      text.to_s.downcase.split(/\W+/).reject do |token|
        token.length < 2 || STOPWORDS.include?(token)
      end
    end

    def score(tokens:, route_artifact_ids:)
      route_ids = Set.new(route_artifact_ids)

      scored = @scan.artifacts.to_a.each_with_object([]) do |artifact, scored_artifacts|
        artifact_score = score_artifact(artifact, tokens)
        artifact_score *= PAGE_CONTEXT_BOOST if route_ids.include?(artifact.id)

        scored_artifacts << [artifact, artifact_score] if artifact_score >= 1.0
      end

      scored.sort { |left, right| compare_scores(left, right) }
    end

    def compare_scores(left, right)
      score_comparison = right.last <=> left.last
      return score_comparison unless score_comparison.zero?

      left.first.path <=> right.first.path
    end

    def score_artifact(artifact, tokens)
      score_text(tokens, artifact.summary, 1.0) +
        score_text(tokens, artifact.public_symbols, 2.0) +
        score_text(tokens, artifact.path, 1.5)
    end

    def score_text(tokens, value, weight)
      terms = searchable_terms(value)

      tokens.inject(0.0) do |total, token|
        token_matches_terms?(token, terms) ? total + weight : total
      end
    end

    def searchable_terms(value)
      Array(value).flat_map { |entry| tokenize(entry) }
    end

    def token_matches_terms?(token, terms)
      terms.any? { |term| term == token || term.include?(token) }
    end

    def artifact_ids_for_route(page_context)
      path = page_context_path(page_context)
      return [] if path.nil?

      route = Rails.application.routes.recognize_path(path)
      artifact_ids_for_route_params(route)
    rescue URI::InvalidURIError, ActionController::RoutingError
      []
    end

    def page_context_path(page_context)
      return nil unless page_context.respond_to?(:[])

      url = page_context[:url] || page_context["url"]
      return nil if url.to_s.empty?

      path = URI.parse(url.to_s).path
      path = "/" if path.to_s.empty?
      path.start_with?("/") ? path : "/#{path}"
    end

    def artifact_ids_for_route_params(route)
      controller, action = controller_and_action(route)
      return [] if controller.to_s.empty? || action.to_s.empty?

      controller_path = "app/controllers/#{controller}_controller.rb"
      view_prefix = "app/views/#{controller}/#{action}"

      @scan.artifacts.select { |artifact| route_artifact?(artifact, controller_path, view_prefix) }.map(&:id)
    end

    def controller_and_action(route)
      [route[:controller] || route["controller"], route[:action] || route["action"]]
    end

    def route_artifact?(artifact, controller_path, view_prefix)
      artifact.path == controller_path || artifact.path.start_with?(view_prefix)
    end

    def citation_for(artifact, artifact_score)
      {
        path: artifact.path,
        kind: artifact.kind,
        score: artifact_score.round(2),
        snippet: snippet_for(artifact)
      }
    end

    def snippet_for(artifact)
      summary = artifact.summary.to_s.strip
      return artifact.path if summary.empty?

      summary.split(/(?<=[.!?])\s+/).first
    end
  end
end
