# frozen_string_literal: true

module RubySage
  module Knowledge
    # Idempotently upserts an array of YAML-loaded entries into the
    # +ruby_sage_knowledge_chunks+ table, mapping each entry to a
    # +KnowledgeChunk+ with +source: "yaml"+.
    #
    # Admin-authored rows (+source: "admin_ui"+) are never touched.
    # YAML-sourced rows whose slugs are absent from the current entries
    # array are removed (we treat the YAML directory as the canonical
    # source for everything tagged +source: "yaml"+).
    class Syncer
      Result = Struct.new(:created, :updated, :unchanged, :removed, keyword_init: true) do
        def total_in
          created + updated + unchanged
        end
      end

      ATTRS = %w[title body tags audiences position published url video_url].freeze

      # @param entries [Array<Hash>]
      def initialize(entries:)
        @entries = entries
      end

      # @return [Result]
      def run
        created = 0
        updated = 0
        unchanged = 0

        seen_slugs = []

        @entries.each do |entry|
          slug = entry.fetch("slug")
          seen_slugs << slug

          existing = KnowledgeChunk.find_by(slug: slug)
          if existing
            if existing.source == "admin_ui"
              # Don't clobber an admin-authored chunk that happens to share a slug.
              # The admin row wins; the YAML entry is ignored with a warning.
              warn_admin_slug_collision(slug, entry["source_file"])
              next
            end

            if apply_changes(existing, entry)
              updated += 1
            else
              unchanged += 1
            end
          else
            create_from_entry(entry)
            created += 1
          end
        end

        removed = remove_stale_yaml_chunks(seen_slugs)

        Result.new(created: created, updated: updated, unchanged: unchanged, removed: removed)
      end

      private

      def apply_changes(chunk, entry)
        new_attrs = attributes_from(entry)
        return false if new_attrs.all? { |k, v| chunk.public_send(k) == v }

        chunk.update!(new_attrs)
        true
      end

      def create_from_entry(entry)
        KnowledgeChunk.create!(attributes_from(entry).merge("slug" => entry["slug"], "source" => "yaml"))
      end

      def attributes_from(entry)
        ATTRS.each_with_object({}) do |attr, memo|
          memo[attr] = entry[attr] if entry.key?(attr)
        end.tap do |attrs|
          attrs["tags"] = Array(attrs["tags"]).map(&:to_s) if attrs.key?("tags")
          attrs["audiences"] = Array(attrs["audiences"]).map(&:to_s) if attrs.key?("audiences")
        end
      end

      def remove_stale_yaml_chunks(seen_slugs)
        stale = KnowledgeChunk.from_yaml.where.not(slug: seen_slugs)
        count = stale.count
        stale.destroy_all
        count
      end

      def warn_admin_slug_collision(slug, source_file)
        return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

        Rails.logger.warn(
          "[RubySage] YAML entry slug=#{slug.inspect} from #{source_file} " \
          "collides with an admin-authored chunk; keeping the admin row."
        )
      end
    end
  end
end
