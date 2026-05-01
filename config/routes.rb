# frozen_string_literal: true

RubySage::Engine.routes.draw do
  get "/health", to: "health#show"

  post "/chat", to: "chat#create"

  namespace :admin do
    resources :scans, only: %i[index create]
    resources :artifacts, only: %i[index]
  end

  scope :internal do
    post "/retrieve", to: "internal/retrieve#create"
  end
end
