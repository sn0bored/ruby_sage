# frozen_string_literal: true

module RubySage
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end
