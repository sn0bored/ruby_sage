# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::Tools::DatabaseQuery do
  let(:scan) { RubySage::Scan.create!(status: "completed", finished_at: Time.current) }

  before do
    RubySage::Artifact.delete_all
    RubySage::Scan.delete_all
  end

  after do
    RubySage::Artifact.delete_all
    RubySage::Scan.delete_all
  end

  describe "anthropic tool definition" do
    it "exposes a stable name and a JSON schema with required sql" do
      definition = described_class.to_anthropic

      expect(definition["name"]).to eq("query_database")
      expect(definition["input_schema"]["required"]).to eq(%w[sql])
      expect(definition["description"]).to include("SELECT")
    end
  end

  describe "#call" do
    it "delegates to the SafeExecutor and returns its result" do
      RubySage::Artifact.create!(scan: scan, path: "a", kind: "model", digest: "1")

      result = described_class.new.call(input: { "sql" => "SELECT path FROM ruby_sage_artifacts" })

      expect(result[:rows]).to eq([["a"]])
    end

    it "returns a tool error for missing sql" do
      result = described_class.new.call(input: {})

      expect(result).to eq(error: "tool_input_error", message: "Missing required parameter: sql")
    end

    it "converts UnsafeQuery into a structured tool error" do
      result = described_class.new.call(input: { "sql" => "DELETE FROM ruby_sage_scans" })

      expect(result[:error]).to eq("tool_input_error")
      expect(result[:message]).to include("Query rejected")
    end
  end
end
