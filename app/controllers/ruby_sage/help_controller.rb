# frozen_string_literal: true

module RubySage
  # Read-only browsable index of curated knowledge entries — the "I don't know
  # where to start" landing page. Admin CRUD lives at +/ruby_sage/admin/knowledge+.
  class HelpController < ApplicationController
    def index
      mode = RubySage.configuration.mode
      @query = params[:q].to_s.strip
      @active_tag = params[:tag].presence

      @chunks = filtered_chunks(@query, mode)
      @tags = @chunks.flat_map { |chunk| Array(chunk.tags) }.tally.sort_by { |_tag, count| -count }
      @chunks = @chunks.select { |c| Array(c.tags).map(&:to_s).include?(@active_tag) } if @active_tag
    end

    def show
      mode = RubySage.configuration.mode
      @chunk = KnowledgeChunk.published.find_by!(slug: params[:slug])

      head :not_found and return unless @chunk.visible_in_mode?(mode)
    end

    private

    def filtered_chunks(query, mode)
      scope = KnowledgeChunk.published.ordered
      if query.present?
        term = like_term(query)
        scope = scope.where(search_sql, term, term, term, term)
      end
      scope.to_a.select { |chunk| chunk.visible_in_mode?(mode) }
    end

    def search_sql
      <<~SQL.squish
        LOWER(title) LIKE ? OR LOWER(body) LIKE ? OR LOWER(slug) LIKE ? OR LOWER(COALESCE(tags, '')) LIKE ?
      SQL
    end

    def like_term(query)
      "%#{query.downcase.gsub(/[%_]/) { |c| "\\#{c}" }}%"
    end
  end
end
