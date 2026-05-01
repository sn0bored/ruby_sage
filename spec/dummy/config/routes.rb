# frozen_string_literal: true

Rails.application.routes.draw do
  root "posts#index"

  resources :posts, only: %i[index show]

  mount RubySage::Engine => "/ruby_sage"
end
