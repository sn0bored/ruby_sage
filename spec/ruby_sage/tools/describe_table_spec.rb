# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::Tools::DescribeTable do
  it "returns column metadata for a known table" do
    result = described_class.new.call(input: { "table_name" => "ruby_sage_artifacts" })

    expect(result[:table_name]).to eq("ruby_sage_artifacts")
    column_names = result[:columns].pluck(:name)
    expect(column_names).to include("path", "digest", "summary")
  end

  it "returns an error for an unknown table" do
    result = described_class.new.call(input: { "table_name" => "nope" })

    expect(result).to eq(error: "tool_input_error", message: "Unknown table: nope")
  end

  it "returns a tool error when table_name is missing" do
    result = described_class.new.call(input: {})

    expect(result[:error]).to eq("tool_input_error")
  end

  it "exposes an Anthropic-compatible tool definition" do
    expect(described_class.to_anthropic["name"]).to eq("describe_table")
    expect(described_class.to_anthropic["input_schema"]["required"]).to eq(%w[table_name])
  end
end
