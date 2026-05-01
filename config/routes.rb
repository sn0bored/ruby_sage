# frozen_string_literal: true

RubySage::Engine.routes.draw do
  get "/health", to: "health#show"

  scope :internal do
    post "/retrieve", to: "internal/retrieve#create"
  end
end
