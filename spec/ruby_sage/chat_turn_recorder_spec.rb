# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::ChatTurnRecorder do
  let(:controller) { instance_double(ActionController::Base) }
  let(:scan) { RubySage::Scan.create!(status: "completed", finished_at: Time.current) }
  let(:retrieval) do
    {
      scan_id: scan.id,
      citations: [{ path: "app/models/post.rb", kind: "model", score: 4.5 }]
    }
  end
  let(:result) do
    {
      answer: "It does X.",
      tool_calls: [{ id: "c1", name: "describe_table", input: { "table_name" => "posts" } }],
      iterations: 2,
      usage: {
        input_tokens: 100, output_tokens: 25,
        cache_read_input_tokens: 500, cache_creation_input_tokens: 5
      }
    }
  end

  before do
    RubySage.reset_configuration!
    RubySage::ChatTurn.delete_all
  end

  after { RubySage.reset_configuration! }

  it "persists a completed turn with question, answer, citations, tool_calls, usage" do
    turn = described_class.new(controller: controller).call(
      question: "what does Post do?", retrieval: retrieval, result: result, status: "completed"
    )

    expect(turn).to be_persisted
    expect(turn).to have_attributes(
      question: "what does Post do?",
      answer: "It does X.",
      input_tokens: 100,
      output_tokens: 25,
      cache_read_tokens: 500,
      iterations: 2,
      scan_id: scan.id
    )
    expect(turn.tool_calls.first["name"]).to eq("describe_table")
    expect(turn.citations.first["path"]).to eq("app/models/post.rb")
  end

  it "persists a failed turn with error_message and no answer" do
    turn = described_class.new(controller: controller).call(
      question: "anything", retrieval: nil, result: nil,
      status: "failed", error_message: "upstream went boom"
    )

    expect(turn.status).to eq("failed")
    expect(turn.error_message).to eq("upstream went boom")
    expect(turn.answer).to be_nil
  end

  it "returns nil and writes nothing when persist_chat_turns is false" do
    RubySage.configure { |c| c.persist_chat_turns = false }

    expect do
      described_class.new(controller: controller).call(
        question: "q", retrieval: retrieval, result: result, status: "completed"
      )
    end.not_to change(RubySage::ChatTurn, :count)
  end

  it "honors config.identify_asker when it returns an ActiveRecord object" do
    asker = scan
    RubySage.configure { |c| c.identify_asker = ->(_controller) { asker } }

    turn = described_class.new(controller: controller).call(
      question: "q", retrieval: retrieval, result: result, status: "completed"
    )

    expect(turn.asker).to eq(asker)
  end

  it "ignores non-ActiveRecord results from identify_asker" do
    RubySage.configure { |c| c.identify_asker = ->(_controller) { "not an AR record" } }

    turn = described_class.new(controller: controller).call(
      question: "q", retrieval: retrieval, result: result, status: "completed"
    )

    expect(turn.asker).to be_nil
  end
end
