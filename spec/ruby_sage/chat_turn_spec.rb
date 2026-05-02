# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::ChatTurn do
  let(:scan) { RubySage::Scan.create!(status: "completed", finished_at: Time.current) }

  before do
    described_class.delete_all
    RubySage::Artifact.delete_all
    RubySage::Scan.delete_all
  end

  after do
    described_class.delete_all
    RubySage::Artifact.delete_all
    RubySage::Scan.delete_all
  end

  it "validates required fields" do
    turn = described_class.new
    expect(turn).not_to be_valid
    expect(turn.errors[:mode]).to be_present
    expect(turn.errors[:question]).to be_present
  end

  it "serializes tool_calls and citations as JSON" do
    turn = described_class.create!(
      scan: scan, mode: "admin", question: "who?", answer: "the author",
      tool_calls: [{ name: "describe_table", input: { "table_name" => "posts" } }],
      citations: [{ path: "app/models/post.rb", kind: "model", score: 4.5 }],
      input_tokens: 100, output_tokens: 50
    )

    reloaded = described_class.find(turn.id)
    expect(reloaded.tool_calls.first["name"]).to eq("describe_table")
    expect(reloaded.citations.first["path"]).to eq("app/models/post.rb")
  end

  describe "scopes and helpers" do
    let!(:dev_turn) { described_class.create!(mode: "developer", question: "q", status: "completed") }
    let!(:admin_turn_with_tools) do
      described_class.create!(
        mode: "admin", question: "q", status: "completed",
        tool_calls: [{ name: "query_database", input: { "sql" => "SELECT 1" } }]
      )
    end
    let!(:failed_turn) { described_class.create!(mode: "user", question: "q", status: "failed") }

    it ".for_mode filters by mode" do
      expect(described_class.for_mode(:admin)).to contain_exactly(admin_turn_with_tools)
    end

    it ".failed returns only failed turns" do
      expect(described_class.failed).to contain_exactly(failed_turn)
    end

    it ".with_tool_calls returns only turns that invoked at least one tool" do
      expect(described_class.with_tool_calls).to contain_exactly(admin_turn_with_tools)
    end

    it "#used_tools? is true only when tool_calls is non-empty" do
      expect(dev_turn.used_tools?).to be(false)
      expect(admin_turn_with_tools.used_tools?).to be(true)
    end
  end

  it "#total_tokens sums input + output ignoring cache" do
    turn = described_class.create!(
      mode: "admin", question: "q", status: "completed",
      input_tokens: 100, output_tokens: 25, cache_read_tokens: 500, cache_creation_tokens: 5
    )
    expect(turn.total_tokens).to eq(125)
  end
end
