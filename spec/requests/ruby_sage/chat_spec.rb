# frozen_string_literal: true

require "rails_helper"

RSpec.describe "RubySage chat", type: :request do
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
    post "/ruby_sage/chat", params: { message: "posts" }, as: :json

    expect(response).to have_http_status(:forbidden)
  end

  it "returns bad request when the message param is missing" do
    allow_access

    post "/ruby_sage/chat", params: {}, as: :json

    expect(response).to have_http_status(:bad_request)
  end

  it "returns an answer with citations, scan id, and usage" do
    allow_access
    scan = seed_completed_scan
    stub_provider(provider_response)

    post "/ruby_sage/chat", params: chat_params, as: :json

    expect_successful_chat_response(scan)
  end

  it "returns bad gateway when the provider fails" do
    allow_access
    stub_failing_provider

    post "/ruby_sage/chat", params: { message: "posts" }, as: :json

    expect(response).to have_http_status(:bad_gateway)
  end

  def allow_access
    RubySage.configure { |config| config.auth_check = ->(_controller) { true } }
  end

  def seed_completed_scan
    scan = RubySage::Scan.create!(status: "completed", finished_at: Time.current)
    RubySage::Artifact.create!(
      scan: scan,
      path: "app/controllers/posts_controller.rb",
      kind: "controller",
      digest: SecureRandom.hex(8),
      summary: "PostsController lists synthetic posts.",
      public_symbols: ["PostsController#index"]
    )
    scan
  end

  def stub_provider(response)
    provider = instance_double(RubySage::Providers::Base, chat: response)

    allow(RubySage).to receive(:provider).and_return(provider)
  end

  def stub_failing_provider
    provider = instance_double(RubySage::Providers::Base)
    allow(provider).to receive(:chat).and_raise(RubySage::Providers::ProviderError, "upstream failed")
    allow(RubySage).to receive(:provider).and_return(provider)
  end

  def chat_params
    {
      message: "posts",
      page_context: {
        url: "https://example.com/posts",
        title: "Posts"
      }
    }
  end

  def provider_response
    {
      answer: "PostsController#index lists posts.",
      citations: [],
      usage: {
        input_tokens: 12,
        output_tokens: 7
      }
    }
  end

  def expect_successful_chat_response(scan)
    expect(response).to have_http_status(:ok)
    expect_successful_payload(scan)
    expect_successful_citation
  end

  def expect_successful_payload(scan)
    expect(response.parsed_body).to include(
      "answer" => "PostsController#index lists posts.",
      "scan_id" => scan.id,
      "usage" => { "input_tokens" => 12, "output_tokens" => 7 }
    )
  end

  def expect_successful_citation
    expect(response.parsed_body["citations"].first).to include(
      "path" => "app/controllers/posts_controller.rb",
      "kind" => "controller"
    )
  end
end
