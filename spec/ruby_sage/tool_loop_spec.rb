# frozen_string_literal: true

require "json"
require "rails_helper"

RSpec.describe RubySage::ToolLoop do
  let(:registry) do
    RubySage::Tools::Registry.new(tools: [echo_tool])
  end
  let(:echo_tool) do
    Class.new(RubySage::Tools::Base) do
      def self.name
        "echo"
      end

      def self.description
        "Echoes input."
      end

      def self.input_schema
        { "type" => "object" }
      end

      def call(input:)
        { echoed: input }
      end
    end.new
  end

  describe "no-tool flow" do
    it "returns the model's first answer when no tool_use is requested" do
      provider = instance_double(RubySage::Providers::Base, chat: {
                                   answer: "Hi.", tool_calls: [], usage: { input_tokens: 1 },
                                   stop_reason: "end_turn",
                                   raw_content: [{ "type" => "text", "text" => "Hi." }]
                                 })

      result = described_class.new(registry: registry, provider: provider, max_iterations: 3).run(
        system_prompt: "system", cached_context: "ctx", messages: [{ role: "user", content: "hello" }]
      )

      expect(result[:answer]).to eq("Hi.")
      expect(result[:tool_calls]).to eq([])
      expect(result[:iterations]).to eq(1)
    end
  end

  describe "tool loop flow" do
    it "dispatches tool_use, appends results, and finishes when the model stops calling tools" do
      provider = instance_double(RubySage::Providers::Base)
      allow(provider).to receive(:chat).and_return(tool_use_response, final_response)

      result = described_class.new(registry: registry, provider: provider, max_iterations: 5).run(
        system_prompt: "system", cached_context: "ctx", messages: [{ role: "user", content: "echo hi" }]
      )

      expect(result[:tool_calls]).to eq([{ id: "call_1", name: "echo", input: { "msg" => "hi" } }])
      expect(result[:answer]).to eq("Done.")
      expect(result[:iterations]).to eq(2)
    end

    it "stops at max_iterations even if the model keeps requesting tools" do
      provider = instance_double(RubySage::Providers::Base)
      allow(provider).to receive(:chat).and_return(tool_use_response).at_least(:once)

      result = described_class.new(registry: registry, provider: provider, max_iterations: 2).run(
        system_prompt: "system", cached_context: "ctx", messages: [{ role: "user", content: "loop" }]
      )

      expect(result[:iterations]).to eq(2)
      expect(provider).to have_received(:chat).twice
    end
  end

  def tool_use_response
    {
      answer: "",
      tool_calls: [{ id: "call_1", name: "echo", input: { "msg" => "hi" } }],
      usage: { input_tokens: 5 },
      stop_reason: "tool_use",
      raw_content: [
        { "type" => "tool_use", "id" => "call_1", "name" => "echo", "input" => { "msg" => "hi" } }
      ]
    }
  end

  def final_response
    {
      answer: "Done.",
      tool_calls: [],
      usage: { input_tokens: 10 },
      stop_reason: "end_turn",
      raw_content: [{ "type" => "text", "text" => "Done." }]
    }
  end
end
