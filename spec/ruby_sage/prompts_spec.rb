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

    it "user prompt avoids technical jargon guidance" do
      expect(described_class::USER).to include("plain language")
      expect(described_class::USER).to include("no jargon")
    end
  end
end
