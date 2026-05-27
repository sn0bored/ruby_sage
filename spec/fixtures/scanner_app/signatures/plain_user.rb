# frozen_string_literal: true

MAX_LENGTH = 120

class User < ApplicationRecord
  include Searchable
  extend ClassMethods
  prepend Trackable

  def active?(name, opts: nil, **extra)
    name && opts && extra
  end

  def self.recent(limit = 10)
    [limit]
  end

  private

  def token
    nil
  end
end
