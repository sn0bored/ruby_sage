# frozen_string_literal: true

require "rails_helper"

RSpec.describe "RubySage engine" do
  it "is mounted in the dummy app" do
    expect(Rails.application.routes.url_helpers.ruby_sage_path).to eq("/ruby_sage")
  end
end
