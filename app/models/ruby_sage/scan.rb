# frozen_string_literal: true

module RubySage
  # Represents a single scan of the host application's codebase.
  # @!attribute status
  #   @return [String] "pending", "running", "completed", or "failed"
  class Scan < ApplicationRecord
    self.table_name = "ruby_sage_scans"

    has_many :artifacts, class_name: "RubySage::Artifact", dependent: :destroy, inverse_of: :scan
    has_many :chat_turns, class_name: "RubySage::ChatTurn", dependent: :nullify, inverse_of: :scan

    validates :status, inclusion: { in: %w[pending running completed failed] }

    scope :latest_completed, -> { where(status: "completed").order(finished_at: :desc) }
  end
end
