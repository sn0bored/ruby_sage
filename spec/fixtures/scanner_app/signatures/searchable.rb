# frozen_string_literal: true

module Searchable
  extend ActiveSupport::Concern

  def matches?(query)
    query.to_s
  end

  protected

  def searchable?
    true
  end
end
