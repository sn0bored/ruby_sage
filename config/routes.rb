# frozen_string_literal: true

RubySage::Engine.routes.draw do
  get "/health", to: "health#show"

  post "/chat", to: "chat#create"

  namespace :admin do
    resources :scans, only: %i[index create]
    resources :artifacts, only: %i[index]
    resources :chat_turns, only: %i[index show]
    resources :knowledge_chunks, param: :slug do
      member do
        post :move_up
        post :move_down
      end
      collection do
        post :sync_yaml
      end
    end
  end

  resources :help, only: %i[index show], controller: "help", param: :slug

  scope :internal do
    post "/retrieve", to: "internal/retrieve#create"
  end
end
