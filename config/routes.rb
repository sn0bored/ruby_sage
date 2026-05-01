# frozen_string_literal: true

RubySage::Engine.routes.draw do
  # Filled in by phases 3 + 4. Placeholder route below ensures the engine
  # mounts cleanly and tests can verify the auth gate.
  get "/health", to: "health#show"
end
