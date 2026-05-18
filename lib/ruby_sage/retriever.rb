# frozen_string_literal: true

require "set"
require "uri"

module RubySage
  # Given a natural-language query and optional page URL, retrieves the most
  # relevant artifacts AND curated knowledge chunks for the configured mode,
  # with citations.
  #
  # @example
  #   result = RubySage::Retriever.new.call(query: "how do I run the report?")
  #   result[:artifacts]   # auto-summarized code
  #   result[:knowledge]   # human-curated how-tos
  #   result[:citations]   # mixed, score-sorted
  # Scoring + ranking sit alongside route resolution and citation shaping here.
  # Splitting into smaller classes would fragment the read order of a single
  # algorithmic pipeline, so we accept the class size.
  class Retriever # rubocop:disable Metrics/ClassLength
    DEFAULT_LIMIT = 10
    PAGE_CONTEXT_BOOST = 2.5

    STOPWORDS = Set.new(%w[a an the is are was were in on at to of for and or but that this it we our my your]).freeze
    private_constant :STOPWORDS

    # @param scan [RubySage::Scan, nil]
    # @param limit [Integer] total citation budget across artifacts + knowledge.
    # @param mode [Symbol, nil]
    def initialize(scan: Scan.latest_completed.first, limit: DEFAULT_LIMIT, mode: nil)
      @scan = scan
      @limit = limit
      @mode = (mode || RubySage.configuration.mode || :developer).to_sym
    end

    # @param query [String]
    # @param page_context [Hash, nil]
    # @return [Hash]
    def call(query:, page_context: nil)
      tokens = tokenize(query)

      artifact_pairs = retrieve_artifacts(tokens: tokens, page_context: page_context)
      knowledge_pairs = retrieve_knowledge(tokens: tokens)

      mixed = (artifact_pairs + knowledge_pairs).sort_by { |_item, score| -score }.first(@limit)

      {
        artifacts: mixed.map(&:first).grep(Artifact),
        knowledge: mixed.map(&:first).grep(KnowledgeChunk),
        citations: mixed.map { |item, score| citation_for(item, score) },
        scan_id: @scan&.id
      }
    end

    private

    def retrieve_artifacts(tokens:, page_context:)
      return [] if @scan.nil?

      route_ids = Set.new(artifact_ids_for_route(page_context))
      candidates = @scan.artifacts.to_a.select { |artifact| artifact.visible_in_mode?(@mode) }

      candidates.each_with_object([]) do |artifact, scored|
        artifact_score = score_artifact(artifact, tokens)
        artifact_score *= PAGE_CONTEXT_BOOST if route_ids.include?(artifact.id)
        scored << [artifact, artifact_score] if artifact_score >= 1.0
      end
    end

    def retrieve_knowledge(tokens:)
      return [] unless knowledge_table_exists?

      boost = RubySage.configuration.knowledge_boost.to_f
      KnowledgeChunk.published.to_a.each_with_object([]) do |chunk, scored|
        next unless chunk.visible_in_mode?(@mode)

        chunk_score = score_knowledge(chunk, tokens) * boost
        scored << [chunk, chunk_score] if chunk_score >= 1.0
      end
    end

    def knowledge_table_exists?
      ActiveRecord::Base.connection.data_source_exists?("ruby_sage_knowledge_chunks")
    rescue StandardError
      false
    end

    def tokenize(text)
      text.to_s.downcase.split(/\W+/).reject do |token|
        token.length < 2 || STOPWORDS.include?(token)
      end
    end

    def score_artifact(artifact, tokens)
      score_text(tokens, artifact.summary, 1.0) +
        score_text(tokens, artifact.public_symbols, 2.0) +
        score_text(tokens, artifact.path, 1.5)
    end

    def score_knowledge(chunk, tokens)
      score_text(tokens, chunk.title, 3.0) +
        score_text(tokens, chunk.tags, 2.5) +
        score_text(tokens, chunk.body, 1.0) +
        score_text(tokens, chunk.slug, 1.5)
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
      return [] if @scan.nil?

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

    def citation_for(item, score)
      item.is_a?(KnowledgeChunk) ? knowledge_citation(item, score) : artifact_citation(item, score)
    end

    def knowledge_citation(chunk, score)
      {
        kind: "knowledge",
        slug: chunk.slug,
        title: chunk.title,
        tags: Array(chunk.tags),
        score: score.round(2),
        snippet: knowledge_snippet(chunk)
      }
    end

    def artifact_citation(artifact, score)
      {
        kind: artifact.kind || "artifact",
        path: artifact.path,
        score: score.round(2),
        snippet: artifact_snippet(artifact)
      }
    end

    def artifact_snippet(artifact)
      summary = artifact.summary.to_s.strip
      return artifact.path if summary.empty?

      summary.split(/(?<=[.!?])\s+/).first
    end

    def knowledge_snippet(chunk)
      body = plain_text(chunk.body)
      return chunk.title if body.empty?

      first_sentence = body.split(/\n\n|(?<=[.!?])\s+/).first.to_s
      first_sentence.length > 200 ? "#{first_sentence[0, 197]}..." : first_sentence
    end

    # Strips HTML tags, kramdown attribute blocks, and markdown formatting so
    # citation snippets display as clean human-readable text.
    def plain_text(markdown)
      text = markdown.to_s
      text = text.gsub(/<[^>]+>/, " ")                       # HTML tags
      text = text.gsub(/\{:[^}]*\}/, "")                     # kramdown IAL like {::} or {:.cls}
      text = text.gsub(/!\[([^\]]*)\]\([^)]*\)/, '\1')       # ![alt](url) -> alt
      text = text.gsub(/\[([^\]]+)\]\([^)]*\)/, '\1')        # [text](url) -> text
      text = text.gsub(/[`*_~]+/, "")                        # ` * _ ~
      text = text.gsub(/^#+\s*/m, "")                        # leading # headers
      text = text.gsub(/&amp;/, "&").gsub(/&lt;/, "<").gsub(/&gt;/, ">").gsub(/&quot;/, '"')
      text.squeeze(" ").strip
    end
  end
end
