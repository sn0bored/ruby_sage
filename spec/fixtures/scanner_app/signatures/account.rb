# frozen_string_literal: true

class Account < ApplicationRecord
  has_many :posts, dependent: :destroy
  belongs_to :owner, class_name: "User"

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates_length_of :name, maximum: 120

  enum status: { active: 0, archived: 1 }

  scope :active, ->(limit = 10) { where(status: :active).limit(limit) }
end
