# frozen_string_literal: true

Rails.application.routes.draw do
  mount RubySage::Engine => "/ruby_sage"
end
