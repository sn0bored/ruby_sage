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
    post "/ruby_sage/chat", params: { messages: [{ role: "user", content: "posts" }] }, as: :json

    expect(response).to have_http_status(:forbidden)
  end

  it "returns bad request when neither message nor messages param is present" do
    allow_access

    post "/ruby_sage/chat", params: {}, as: :json

    expect(response).to have_http_status(:bad_request)
  end

  context "with single message param (legacy format)" do
    it "returns an answer" do
      allow_access
      seed_completed_scan
      stub_provider(provider_response)

      post "/ruby_sage/chat", params: { message: "posts" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["answer"]).to eq("PostsController#index lists posts.")
    end
  end

  context "with messages array (multi-turn format)" do
    it "returns an answer with citations, scan id, and usage" do
      allow_access
      scan = seed_completed_scan
      stub_provider(provider_response)

      post "/ruby_sage/chat", params: multi_turn_params, as: :json

      expect_successful_chat_response(scan)
    end

    it "passes the full conversation history to the provider" do
      allow_access
      seed_completed_scan
      provider = stub_provider(provider_response)

      post "/ruby_sage/chat", params: multi_turn_params, as: :json

      expect(provider).to have_received(:chat) do |kwargs|
        messages = kwargs[:messages]
        expect(messages.map { |m| m[:role] }).to eq(%w[user assistant user])
      end
    end

    it "uses the last user message as the retrieval query" do
      allow_access
      seed_completed_scan
      stub_provider(provider_response)
      retriever = instance_double(RubySage::Retriever, call: empty_retrieval)
      allow(RubySage::Retriever).to receive(:new).and_return(retriever)

      post "/ruby_sage/chat", params: multi_turn_params, as: :json

      expect(retriever).to have_received(:call).with(
        hash_including(query: "follow up question about posts")
      )
    end
  end

  it "returns bad gateway when the provider fails" do
    allow_access
    stub_failing_provider

    post "/ruby_sage/chat", params: { message: "posts" }, as: :json

    expect(response).to have_http_status(:bad_gateway)
  end

  context "with mode: :developer (default)" do
    it "sends the developer system prompt to the provider" do
      allow_access
      seed_completed_scan
      provider = stub_provider(provider_response)

      post "/ruby_sage/chat", params: { message: "posts" }, as: :json

      expect(provider).to have_received(:chat) do |kwargs|
        expect(kwargs[:system_prompt]).to include("source code")
      end
    end
  end

  context "with mode: :admin" do
    it "sends the admin system prompt to the provider" do
      RubySage.configure do |c|
        c.auth_check = ->(_) { true }
        c.mode = :admin
      end
      seed_completed_scan
      provider = stub_provider(provider_response)

      post "/ruby_sage/chat", params: { message: "billing" }, as: :json

      expect(provider).to have_received(:chat) do |kwargs|
        expect(kwargs[:system_prompt]).to include("workflows")
      end
    end
  end

  context "with mode: :user" do
    it "sends the user system prompt to the provider" do
      RubySage.configure do |c|
        c.auth_check = ->(_) { true }
        c.mode = :user
      end
      seed_completed_scan
      provider = stub_provider(provider_response)

      post "/ruby_sage/chat", params: { message: "how do I login?" }, as: :json

      expect(provider).to have_received(:chat) do |kwargs|
        expect(kwargs[:system_prompt]).to include("plain language")
      end
    end
  end

  context "with mode: :admin and enable_database_queries" do
    before do
      RubySage.configure do |c|
        c.auth_check = ->(_) { true }
        c.mode = :admin
        c.enable_database_queries = true
      end
      seed_completed_scan
    end

    it "sends the database-tools addendum AND the tools array to the provider" do
      provider = stub_provider(tool_use_response, final_response)

      post "/ruby_sage/chat", params: { message: "who is the author of post 47?" }, as: :json

      expect(provider).to have_received(:chat).at_least(:once) do |kwargs|
        expect(kwargs[:system_prompt]).to include("query_database")
        expect(kwargs[:tools].map { |t| t["name"] }).to include("query_database", "describe_table")
      end
    end

    it "returns tool_calls and iterations in the response when the model invoked a tool" do
      stub_provider(tool_use_response, final_response)

      post "/ruby_sage/chat", params: { message: "anything" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["tool_calls"]).to be_an(Array)
      expect(response.parsed_body["iterations"]).to eq(2)
    end

    it "appends the query_scope hint to the system prompt when configured" do
      RubySage.configure { |c| c.query_scope = ->(_controller) { "organization_id = 99" } }
      provider = stub_provider(final_response)

      post "/ruby_sage/chat", params: { message: "show me users" }, as: :json

      expect(provider).to have_received(:chat).at_least(:once) do |kwargs|
        expect(kwargs[:system_prompt]).to include("organization_id = 99")
      end
    end
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

  def stub_provider(*responses)
    provider = instance_double(RubySage::Providers::Base)
    allow(provider).to receive(:chat).and_return(*responses)
    allow(RubySage).to receive(:provider).and_return(provider)
    provider
  end

  def stub_failing_provider
    provider = instance_double(RubySage::Providers::Base)
    allow(provider).to receive(:chat).and_raise(RubySage::Providers::ProviderError, "upstream failed")
    allow(RubySage).to receive(:provider).and_return(provider)
  end

  def multi_turn_params
    {
      messages: [
        { role: "user", content: "tell me about posts" },
        { role: "assistant", content: "PostsController handles post CRUD." },
        { role: "user", content: "follow up question about posts" }
      ],
      page_context: { url: "https://example.com/posts", title: "Posts" }
    }
  end

  def provider_response
    {
      answer: "PostsController#index lists posts.",
      citations: [],
      usage: { input_tokens: 12, output_tokens: 7 },
      tool_calls: [],
      stop_reason: "end_turn",
      raw_content: [{ "type" => "text", "text" => "PostsController#index lists posts." }]
    }
  end

  def tool_use_response
    {
      answer: "",
      tool_calls: [{ id: "call_1", name: "describe_table", input: { "table_name" => "ruby_sage_artifacts" } }],
      usage: { input_tokens: 30, output_tokens: 5 },
      stop_reason: "tool_use",
      raw_content: [
        { "type" => "tool_use", "id" => "call_1", "name" => "describe_table",
          "input" => { "table_name" => "ruby_sage_artifacts" } }
      ]
    }
  end

  def final_response
    {
      answer: "Found it.",
      tool_calls: [],
      usage: { input_tokens: 50, output_tokens: 8 },
      stop_reason: "end_turn",
      raw_content: [{ "type" => "text", "text" => "Found it." }]
    }
  end

  def empty_retrieval
    { artifacts: [], citations: [], scan_id: nil }
  end

  def expect_successful_chat_response(scan)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(
      "answer" => "PostsController#index lists posts.",
      "scan_id" => scan.id,
      "usage" => { "input_tokens" => 12, "output_tokens" => 7 }
    )
    expect(response.parsed_body["citations"].first).to include(
      "path" => "app/controllers/posts_controller.rb",
      "kind" => "controller"
    )
  end
end
