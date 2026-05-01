# frozen_string_literal: true

module RubySage
  # Reports whether the mounted engine is reachable.
  class HealthController < ApplicationController
    # Renders the engine health payload.
    #
    # @return [void]
    def show
      render json: { status: "ok", version: RubySage::VERSION }
    end
  end
end
