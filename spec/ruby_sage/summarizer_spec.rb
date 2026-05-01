# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::Summarizer do
  before { RubySage.reset_configuration! }

  after { RubySage.reset_configuration! }

  it "returns nil when no api key is configured" do
    summary = described_class.new.summarize(contents: "class Post; end", path: "app/models/post.rb")

    expect(summary).to be_nil
  end

  it "returns nil when the provider fails" do
    provider = instance_double(RubySage::Providers::Base)
    allow(provider).to receive(:chat).and_raise(RubySage::Providers::ProviderError, "upstream failed")
    allow(RubySage).to receive(:provider).and_return(provider)
    RubySage.configure { |config| config.api_key = "test-key" }

    summary = described_class.new.summarize(contents: "class Post; end", path: "app/models/post.rb")

    expect(summary).to be_nil
  end

  it "calls the configured provider when an api key is present" do
    provider = instance_double(RubySage::Providers::Base, chat: { answer: "Post model summary" })
    allow(RubySage).to receive(:provider).and_return(provider)
    RubySage.configure { |config| config.api_key = "test-key" }

    summary = described_class.new.summarize(contents: "class Post; end", path: "app/models/post.rb")

    expect(summary).to eq("Post model summary")
  end
end
