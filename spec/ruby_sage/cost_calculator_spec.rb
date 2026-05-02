# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::CostCalculator do
  before { RubySage.reset_configuration! }
  after { RubySage.reset_configuration! }

  describe ".call" do
    it "returns nil for an unknown model" do
      result = described_class.call(model: "nope-3000", input_tokens: 1000, output_tokens: 500)
      expect(result).to be_nil
    end

    it "returns nil for an empty model name" do
      expect(described_class.call(model: nil, input_tokens: 100)).to be_nil
      expect(described_class.call(model: "", input_tokens: 100)).to be_nil
    end

    it "calculates cost for a known Anthropic model with input + output tokens" do
      cost = described_class.call(
        model: "claude-sonnet-4-6",
        input_tokens: 1_000_000,
        output_tokens: 100_000
      )
      # 1M @ $3 + 100K @ $15 = $3.00 + $1.50 = $4.50
      expect(cost).to be_within(0.001).of(4.50)
    end

    it "applies cache pricing separately" do
      cost = described_class.call(
        model: "claude-sonnet-4-6",
        input_tokens: 0,
        output_tokens: 0,
        cache_read_tokens: 1_000_000,
        cache_creation_tokens: 1_000_000
      )
      # 1M @ $0.30 + 1M @ $3.75 = $4.05
      expect(cost).to be_within(0.001).of(4.05)
    end

    it "calculates cost for OpenAI models without cache fields" do
      cost = described_class.call(
        model: "gpt-4.1",
        input_tokens: 500_000,
        output_tokens: 100_000
      )
      # 500K @ $2 + 100K @ $8 = $1.00 + $0.80 = $1.80
      expect(cost).to be_within(0.001).of(1.80)
    end
  end

  describe "config.model_pricing override" do
    it "merges host overrides on top of defaults" do
      RubySage.configure do |c|
        c.model_pricing = {
          "my-fine-tune" => { input_per_million: 1.0, output_per_million: 2.0 }
        }
      end

      cost = described_class.call(model: "my-fine-tune", input_tokens: 1_000_000, output_tokens: 1_000_000)
      expect(cost).to be_within(0.001).of(3.0)
    end

    it "lets host overrides change a built-in model's pricing" do
      RubySage.configure do |c|
        c.model_pricing = {
          "claude-sonnet-4-6" => { input_per_million: 0.0, output_per_million: 0.0 }
        }
      end

      cost = described_class.call(model: "claude-sonnet-4-6", input_tokens: 1_000_000, output_tokens: 1_000_000)
      expect(cost).to eq(0.0)
    end
  end

  describe ".pricing" do
    it "exposes the merged pricing map" do
      RubySage.configure do |c|
        c.model_pricing = { "custom" => { input_per_million: 0.50 } }
      end
      expect(described_class.pricing).to include("custom", "claude-sonnet-4-6")
    end
  end
end
