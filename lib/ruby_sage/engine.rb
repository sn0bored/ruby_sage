# frozen_string_literal: true

require "rails/engine"

module RubySage
  class Engine < ::Rails::Engine
    isolate_namespace RubySage
  end
end
