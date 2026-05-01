# frozen_string_literal: true

module RubySage
  # Stores the scanner's per-file metadata for a single scan.
  class Artifact < ApplicationRecord
    self.table_name = "ruby_sage_artifacts"

    belongs_to :scan, class_name: "RubySage::Scan", inverse_of: :artifacts

    validates :path, presence: true
    validates :digest, presence: true

    serialize :public_symbols, coder: JSON
    serialize :route_mappings, coder: JSON

    scope :of_kind, ->(kind) { where(kind: kind) }
  end
end
