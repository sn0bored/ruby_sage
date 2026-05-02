# frozen_string_literal: true

module RubySage
  # Decides which RubySage modes (+:developer+, +:admin+, +:user+) a scanned
  # artifact should be visible to. Default heuristic favors safety: most files
  # are developer-only, admin sees user-facing controllers + models + schema +
  # admin namespace, and the +:user+ audience is empty unless the host opts in
  # via +config.audience_for+ or +config.user_facing_paths+.
  #
  # Host apps with their own user-help content can override either by:
  #
  # 1. Setting +config.user_facing_paths+ to an array of glob patterns whose
  #    matches will additionally be tagged +:user+, OR
  # 2. Setting +config.audience_for+ to a callable that takes the per-file
  #    attribute hash and returns an array of audience symbols.
  class AudienceClassifier
    DEVELOPER_ONLY = %w[
      app/services/
      app/jobs/
      app/policies/
      app/queries/
      app/workers/
      app/decorators/
      app/serializers/
      app/components/
      lib/
      config/
    ].freeze
    private_constant :DEVELOPER_ONLY

    DEVELOPER_AND_ADMIN = %w[
      app/models/
      app/controllers/
      app/views/
      app/helpers/
      app/mailers/
      db/schema.rb
    ].freeze
    private_constant :DEVELOPER_AND_ADMIN

    ADMIN_NAMESPACES = %w[
      app/controllers/admin/
      app/views/admin/
      app/admin/
    ].freeze
    private_constant :ADMIN_NAMESPACES

    DEVELOPER_DOCS = %w[README.md CLAUDE.md .cursorrules].freeze
    private_constant :DEVELOPER_DOCS

    # @param config [RubySage::Configuration]
    # @return [RubySage::AudienceClassifier]
    def initialize(config: RubySage.configuration)
      @config = config
    end

    # Returns the audience list for an artifact, as an array of strings.
    # Honors +config.audience_for+ first, then heuristic defaults, then
    # +config.user_facing_paths+ as an additive overlay.
    #
    # @param attributes [Hash] artifact attributes (must include +:path+).
    # @return [Array<String>]
    def call(attributes:)
      override = invoke_override(attributes)
      base = override || default_audiences_for(attributes[:path].to_s)
      with_user_facing_overlay(base, attributes[:path].to_s)
    end

    private

    attr_reader :config

    def invoke_override(attributes)
      callable = config.respond_to?(:audience_for) ? config.audience_for : nil
      return nil if callable.nil?

      result = callable.call(attributes)
      return nil if result.nil?

      Array(result).map(&:to_s).uniq
    end

    def default_audiences_for(path)
      return %w[developer] if DEVELOPER_DOCS.include?(path)
      return %w[developer admin] if admin_visible?(path)
      return %w[developer] if developer_only?(path)

      %w[developer]
    end

    def admin_visible?(path)
      ADMIN_NAMESPACES.any? { |prefix| path.start_with?(prefix) } ||
        DEVELOPER_AND_ADMIN.include?(path) ||
        DEVELOPER_AND_ADMIN.any? { |prefix| prefix.end_with?("/") && path.start_with?(prefix) }
    end

    def developer_only?(path)
      DEVELOPER_ONLY.any? { |prefix| path.start_with?(prefix) }
    end

    def with_user_facing_overlay(base, path)
      patterns = Array(config.respond_to?(:user_facing_paths) ? config.user_facing_paths : nil)
      return base if patterns.empty?

      matched = patterns.any? { |pattern| File.fnmatch?(pattern, path, File::FNM_PATHNAME) }
      return base unless matched

      (base + %w[user]).uniq
    end
  end
end
