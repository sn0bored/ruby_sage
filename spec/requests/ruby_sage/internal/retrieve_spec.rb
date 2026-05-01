# frozen_string_literal: true

require "rails_helper"

RSpec.describe "RubySage internal retrieval", type: :request do
  before do
    RubySage.reset_configuration!
    RubySage::Artifact.delete_all
    RubySage::Scan.delete_all
  end

  after do
    RubySage.reset_configuration!
    RubySage::Artifact.delete_all
    RubySage::Scan.delete_all
  end

  it "returns forbidden by default" do
    post "/ruby_sage/internal/retrieve", params: { query: "posts" }

    expect(response).to have_http_status(:forbidden)
  end

  it "returns retrieved context when the auth check allows access" do
    RubySage.configure { |config| config.auth_check = ->(_controller) { true } }
    seed_fixture_scan

    post "/ruby_sage/internal/retrieve", params: { query: "posts" }, as: :json

    expect_successful_retrieval
  end

  it "returns bad request when the query param is missing" do
    RubySage.configure { |config| config.auth_check = ->(_controller) { true } }

    post "/ruby_sage/internal/retrieve", params: {}, as: :json

    expect(response).to have_http_status(:bad_request)
  end

  def seed_fixture_scan
    scan = RubySage::Scanner.new(host_root: scanner_fixture_root, config: scanner_config).run
    scan.artifacts.find_by!(path: "app/controllers/posts_controller.rb").update!(
      summary: "PostsController lists synthetic posts for the scanner fixture."
    )
  end

  def scanner_fixture_root
    Rails.root.join("../fixtures/scanner_app").expand_path
  end

  def scanner_config
    RubySage::Configuration.new.tap do |configuration|
      configuration.api_key = nil
      configuration.scanner_include = %w[app config db tmp log]
      configuration.scanner_exclude = ["tmp/", "log/", "config/credentials*"]
    end
  end

  def expect_successful_retrieval
    aggregate_failures do
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["citations"].first).to include(
        "path" => "app/controllers/posts_controller.rb",
        "kind" => "controller"
      )
    end
  end
end
