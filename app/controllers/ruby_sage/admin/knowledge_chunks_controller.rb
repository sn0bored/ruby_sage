# frozen_string_literal: true

module RubySage
  module Admin
    # CRUD for curated knowledge entries. Admin-authored rows save with
    # +source: "admin_ui"+; YAML-sourced rows are read-only here (showing
    # an edit form would let an admin change content the YAML file would
    # then clobber on the next sync — confusing). Use the source badge in
    # the index to tell them apart.
    class KnowledgeChunksController < ApplicationController
      before_action :load_chunk,
                    only: %i[show edit update destroy move_up move_down]

      def index
        @chunks = KnowledgeChunk.ordered
      end

      def show; end

      def new
        @chunk = KnowledgeChunk.new(source: "admin_ui")
      end

      def edit
        return if @chunk.source == "admin_ui"

        redirect_to ruby_sage.admin_knowledge_chunk_path(@chunk),
                    alert: "YAML-sourced entries are edited in their source file."
      end

      def create
        @chunk = KnowledgeChunk.new(chunk_params.merge(source: "admin_ui"))
        if @chunk.save
          redirect_to ruby_sage.admin_knowledge_chunks_path,
                      notice: "Knowledge entry created."
        else
          render :new, status: 422
        end
      end

      def update
        if @chunk.source != "admin_ui"
          redirect_to ruby_sage.admin_knowledge_chunk_path(@chunk),
                      alert: "YAML-sourced entries cannot be edited here."
          return
        end

        if @chunk.update(chunk_params)
          redirect_to ruby_sage.admin_knowledge_chunk_path(@chunk),
                      notice: "Knowledge entry updated."
        else
          render :edit, status: 422
        end
      end

      def destroy
        if @chunk.source == "admin_ui"
          @chunk.destroy
          redirect_to ruby_sage.admin_knowledge_chunks_path,
                      notice: "Knowledge entry deleted."
        else
          redirect_to ruby_sage.admin_knowledge_chunks_path,
                      alert: "YAML-sourced entries are deleted by removing them from the YAML file."
        end
      end

      def move_up
        @chunk.move_up
        redirect_to ruby_sage.admin_knowledge_chunks_path
      end

      def move_down
        @chunk.move_down
        redirect_to ruby_sage.admin_knowledge_chunks_path
      end

      def sync_yaml
        entries = Knowledge::Loader.new(path: Knowledge.path).load
        result = Knowledge::Syncer.new(entries: entries).run

        redirect_to ruby_sage.admin_knowledge_chunks_path,
                    notice: "Synced from YAML — #{result.created} created, #{result.updated} updated, " \
                            "#{result.unchanged} unchanged, #{result.removed} removed."
      rescue Knowledge::Loader::InvalidFile => e
        redirect_to ruby_sage.admin_knowledge_chunks_path,
                    alert: "YAML parse error: #{e.message}"
      end

      private

      def load_chunk
        @chunk = KnowledgeChunk.find_by!(slug: params[:slug])
      end

      def chunk_params
        permitted = params.require(:knowledge_chunk).permit(
          :title, :slug, :body, :url, :video_url, :position, :published,
          :tags_string, audiences: []
        ).to_h

        if permitted.key?("tags_string")
          permitted["tags"] = permitted.delete("tags_string").to_s.split(",").map(&:strip).reject(&:empty?)
        end
        permitted["audiences"] = Array(permitted["audiences"]).compact_blank if permitted.key?("audiences")

        permitted
      end
    end
  end
end
