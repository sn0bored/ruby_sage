# frozen_string_literal: true

require "rails_helper"

RSpec.describe "RubySage health", type: :request do
  before { RubySage.reset_configuration! }

  it "returns forbidden by default" do
    get "/ruby_sage/health"

    expect(response).to have_http_status(:forbidden)
  end

  it "returns ok when the auth check allows access" do
    RubySage.configure { |config| config.auth_check = ->(_controller) { true } }

    get "/ruby_sage/health"

    expect(response).to have_http_status(:ok)
  end
end
