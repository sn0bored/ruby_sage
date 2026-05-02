# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::Prompts do
  describe ".for_mode" do
    it "returns the developer prompt for :developer" do
      expect(described_class.for_mode(:developer)).to eq(described_class::DEVELOPER)
    end

    it "returns the admin prompt for :admin" do
      expect(described_class.for_mode(:admin)).to eq(described_class::ADMIN)
    end

    it "returns the user prompt for :user" do
      expect(described_class.for_mode(:user)).to eq(described_class::USER)
    end

    it "accepts a string mode" do
      expect(described_class.for_mode("admin")).to eq(described_class::ADMIN)
    end

    it "falls back to the developer prompt for an unrecognised mode" do
      expect(described_class.for_mode(:unknown)).to eq(described_class::DEVELOPER)
    end

    it "developer prompt references source code" do
      expect(described_class::DEVELOPER).to include("source code")
    end

    it "admin prompt focuses on features and workflows" do
      expect(described_class::ADMIN).to include("features")
      expect(described_class::ADMIN).to include("workflows")
    end

    it "user prompt forbids leaking implementation details" do
      expect(described_class::USER).to include("plain language")
      expect(described_class::USER).to include("Never describe internal architecture")
      expect(described_class::USER).to include("file paths")
      expect(described_class::USER).to include("class or module names")
    end

    it "user prompt gives the model a fixed refusal sentence for how-it-works questions" do
      collapsed = described_class::USER.gsub(/\s+/, " ")
      expect(collapsed).to include(
        'respond exactly: "I can help with how to use the app, but I don\'t have details about how it is built."'
      )
    end
  end
end
