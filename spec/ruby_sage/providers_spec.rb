# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::Providers do
  before { RubySage.reset_configuration! }

  it "returns the Anthropic provider by default" do
    expect(RubySage.provider).to be_a(RubySage::Providers::Anthropic)
  end

  it "returns the configured OpenAI provider" do
    RubySage.configure { |config| config.provider = :openai }

    expect(RubySage.provider).to be_a(RubySage::Providers::OpenAI)
  end

  it "raises for unknown providers" do
    RubySage.configure { |config| config.provider = :unknown }

    expect { RubySage.provider }.to raise_error(ArgumentError, "Unknown provider: unknown")
  end
end
