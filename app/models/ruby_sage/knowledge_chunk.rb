# frozen_string_literal: true

module RubySage
  # A curated piece of knowledge — a how-to, FAQ entry, or workflow doc —
  # authored by the host app's team and retrievable by the chat widget.
  #
  # Three doors read the same rows:
  #
  # - the chat widget (via {RubySage::Retriever}),
  # - the admin CRUD at +/ruby_sage/admin/knowledge+, and
  # - the readable index + show pages at +/ruby_sage/help+.
  #
  # YAML files under +config/ruby_sage/knowledge/*.yml+ are the version-
  # controlled source of truth; +rake ruby_sage:knowledge:sync+ upserts them
  # into this table with +source: "yaml"+. Admin-authored rows carry
  # +source: "admin_ui"+ and are never overwritten by sync.
  class KnowledgeChunk < ApplicationRecord
    self.table_name = "ruby_sage_knowledge_chunks"

    SOURCES = %w[yaml admin_ui].freeze
    AUDIENCES = %w[developer admin user].freeze

    def self.serialize_json(attribute)
      if method(:serialize).parameters.any? { |type, name| type == :key && name == :coder }
        serialize attribute, coder: JSON
      else
        serialize attribute, JSON
      end
    end
    private_class_method :serialize_json

    serialize_json :tags
    serialize_json :audiences
    serialize_json :metadata

    before_validation :assign_slug, on: :create
    before_validation :default_audiences
    before_validation :default_position, on: :create

    validates :slug, presence: true, uniqueness: { case_sensitive: false },
                     format: { with: /\A[a-z0-9-]+\z/, message: "may only contain lowercase letters, numbers, and dashes" }
    validates :title, presence: true, length: { maximum: 255 }
    validates :body, presence: true
    validates :source, inclusion: { in: SOURCES }
    validate  :validate_audiences
    validates :url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true }
    validates :video_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true }

    scope :published,   -> { where(published: true) }
    scope :ordered,     -> { order(Arel.sql("COALESCE(position, 2147483647)"), :id) }
    scope :from_yaml,   -> { where(source: "yaml") }
    scope :from_admin,  -> { where(source: "admin_ui") }

    # Returns chunks whose +audiences+ list contains the given mode (or whose
    # +audiences+ is blank, which we treat as "show everywhere" for parity
    # with {RubySage::Artifact#visible_in_mode?}).
    #
    # @param mode [Symbol, String]
    # @return [ActiveRecord::Relation]
    scope :for_mode, lambda { |mode|
      mode_str = mode.to_s
      # Pure-Ruby filter avoids DB-specific JSON predicates.
      where(id: all.select { |chunk| chunk.visible_in_mode?(mode_str) }.map(&:id))
    }

    # @param mode [Symbol, String]
    # @return [Boolean]
    def visible_in_mode?(mode)
      list = Array(audiences).compact
      return true if list.empty?

      list.map(&:to_s).include?(mode.to_s)
    end

    # Promotes this chunk one slot up in the ordered list.
    # No-op when already first.
    #
    # @return [void]
    def move_up
      neighbor = self.class.where("position < ? OR (position = ? AND id < ?)", position, position, id)
                     .order(position: :desc, id: :desc).first
      swap_position_with(neighbor) if neighbor
    end

    # Demotes this chunk one slot down in the ordered list.
    # No-op when already last.
    #
    # @return [void]
    def move_down
      neighbor = self.class.where("position > ? OR (position = ? AND id > ?)", position, position, id)
                     .order(position: :asc, id: :asc).first
      swap_position_with(neighbor) if neighbor
    end

    # @return [String]
    def to_param
      slug
    end

    # Title used for citations and link text.
    #
    # @return [String]
    def to_s
      title
    end

    private

    def assign_slug
      return if slug.present?
      return if title.blank?

      self.slug = title.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-+|-+$/, "")
    end

    def default_audiences
      self.audiences = [] if audiences.nil?
    end

    def default_position
      self.position ||= (self.class.maximum(:position) || 0) + 1
    end

    def validate_audiences
      return if audiences.nil?

      invalid = Array(audiences).map(&:to_s) - AUDIENCES
      return if invalid.empty?

      errors.add(:audiences, "contains unsupported values: #{invalid.join(', ')}")
    end

    def swap_position_with(other)
      transaction do
        my_pos = position
        update_column(:position, other.position)
        other.update_column(:position, my_pos)
      end
    end
  end
end
