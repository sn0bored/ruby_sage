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

    scope :of_kind, ->(kind) { where(kind: kind) }
  end
end
