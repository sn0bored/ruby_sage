# frozen_string_literal: true

module RubySage
  # Stores the scanner's per-file metadata for a single scan.
  class Artifact < ApplicationRecord
    self.table_name = "ruby_sage_artifacts"

    belongs_to :scan, class_name: "RubySage::Scan", inverse_of: :artifacts

    validates :path, presence: true
    validates :digest, presence: true

    def self.serialize_json(attribute)
      if method(:serialize).parameters.any? { |type, name| type == :key && name == :coder }
        serialize attribute, coder: JSON
      else
        serialize attribute, JSON
      end
    end
    private_class_method :serialize_json

    serialize_json :public_symbols
    serialize_json :route_mappings
    serialize_json :audiences

    # Returns true when this artifact should be visible in the given mode.
    # Artifacts created before audience tagging (no audiences set) are visible
    # in every mode for backwards compatibility.
    #
    # @param mode [Symbol, String]
    # @return [Boolean]
    def visible_in_mode?(mode)
      list = Array(audiences).compact
      return true if list.empty?

      list.map(&:to_s).include?(mode.to_s)
    end

    scope :of_kind, ->(kind) { where(kind: kind) }
  end
end
