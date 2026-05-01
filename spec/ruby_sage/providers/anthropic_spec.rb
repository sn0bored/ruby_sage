# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe RubySage::Providers::Anthropic do
  subject(:provider) { described_class.new(config) }

  let(:config) do
    RubySage::Configuration.new.tap do |configuration|
      configuration.api_key = "anthropic-key"
      configuration.model = "claude-test"
      configuration.request_timeout = 5
    end
  end
  let(:messages) { [{ role: "user", content: "What does PostsController do?" }] }

  it "raises when api_key is nil" do
    config.api_key = nil

    expect { chat }.to raise_error(ArgumentError, "api_key not configured")
  end

  it "posts the expected JSON body and headers" do
    request = stub_successful_request(body: expected_request_body)

    chat

    expect(request).to have_been_requested
  end

  it "parses answer and usage from the response" do
    stub_successful_request(body: expected_request_body)

    expect(chat).to eq(expected_provider_response)
  end

  it "raises ProviderError on non-2xx responses" do
    stub_request(:post, described_class::API_URL).to_return(status: 500, body: "upstream failed")

    expect { chat }.to raise_error(
      RubySage::Providers::ProviderError,
      "Anthropic returned 500: upstream failed"
    )
  end

  def chat
    provider.chat(
      system_prompt: "system",
      cached_context: "cached artifacts",
      messages: messages
    )
  end

  def stub_successful_request(body:)
    stub_request(:post, described_class::API_URL)
      .with(body: body.to_json, headers: expected_headers)
      .to_return(status: 200, body: successful_response.to_json)
  end

  def expected_headers
    {
      "Content-Type" => "application/json",
      "X-Api-Key" => "anthropic-key",
      "Anthropic-Version" => described_class::API_VERSION
    }
  end

  def expected_request_body
    {
      model: "claude-test",
      max_tokens: 1024,
      system: expected_system_blocks,
      messages: messages
    }
  end

  def expected_system_blocks
    [
      { type: "text", text: "system" },
      cached_system_block
    ]
  end

  def cached_system_block
    {
      type: "text",
      text: "cached artifacts",
      cache_control: { type: "ephemeral" }
    }
  end

  def successful_response
    {
      content: [{ type: "text", text: "PostsController lists posts." }],
      usage: successful_usage
    }
  end

  def successful_usage
    {
      input_tokens: 12,
      output_tokens: 7,
      cache_creation_input_tokens: 5,
      cache_read_input_tokens: 2
    }
  end

  def expected_provider_response
    {
      answer: "PostsController lists posts.",
      citations: [],
      usage: {
        input_tokens: 12,
        output_tokens: 7,
        cache_creation_input_tokens: 5,
        cache_read_input_tokens: 2
      }
    }
  end
end
