# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe RubySage::Providers::OpenAI do
  subject(:provider) { described_class.new(config) }

  let(:config) do
    RubySage::Configuration.new.tap do |configuration|
      configuration.api_key = "openai-key"
      configuration.model = "gpt-test"
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
    stub_request(:post, described_class::API_URL).to_return(status: 429, body: "rate limited")

    expect { chat }.to raise_error(
      RubySage::Providers::ProviderError,
      "OpenAI returned 429: rate limited"
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
      "Authorization" => "Bearer openai-key"
    }
  end

  def expected_request_body
    {
      model: "gpt-test",
      max_tokens: 1024,
      messages: [
        { role: "system", content: "system\n\ncached artifacts" },
        { role: "user", content: "What does PostsController do?" }
      ]
    }
  end

  def successful_response
    {
      choices: [
        { message: { content: "PostsController lists posts." } }
      ],
      usage: {
        prompt_tokens: 12,
        completion_tokens: 7,
        total_tokens: 19
      }
    }
  end

  def expected_provider_response
    {
      answer: "PostsController lists posts.",
      citations: [],
      usage: {
        input_tokens: 12,
        output_tokens: 7,
        total_tokens: 19
      }
    }
  end
end
