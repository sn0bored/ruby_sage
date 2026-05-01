# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::SecretRedactor do
  it "redacts YAML secret values" do
    redacted = described_class.new("production:\n  password: hunter2\n").call

    expect(redacted).to eq("production:\n  password: [REDACTED]\n")
  end

  it "preserves ENV references" do
    contents = "Stripe.api_key = ENV[\"STRIPE_SECRET_KEY\"]\n"

    expect(described_class.new(contents).call).to eq(contents)
  end

  it "leaves normal code untouched" do
    contents = "class Post\n  def title = \"Synthetic\"\nend\n"

    expect(described_class.new(contents).call).to eq(contents)
  end
end
