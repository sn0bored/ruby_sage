# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::Configuration do
  let(:default_attributes) do
    {
      provider: :anthropic,
      api_key: nil,
      model: "claude-sonnet-4-6",
      summarization_model: "claude-haiku-4-5",
      auth_check: nil,
      scope: :admin,
      mode: :developer,
      scan_retention: 7,
      csp_nonce: nil,
      request_timeout: 30,
      max_retries: 2
    }
  end

  let(:scanner_include) do
    [
      "app/models",
      "app/controllers",
      "app/services",
      "app/jobs",
      "app/mailers",
      "app/policies",
      "app/queries",
      "app/serializers",
      "app/decorators",
      "app/helpers",
      "app/components",
      "app/workers",
      "app/views",
      "config/routes.rb",
      "db/schema.rb",
      "README.md",
      "CLAUDE.md",
      ".cursorrules"
    ]
  end

  let(:scanner_exclude) do
    [
      "vendor/",
      "node_modules/",
      "tmp/",
      "log/",
      "db/seeds.rb",
      "db/data/",
      "config/credentials*",
      "*.env*",
      "*.key",
      "*.pem"
    ]
  end

  before { RubySage.reset_configuration! }

  it "sets conservative defaults" do
    expect(described_class.new).to have_attributes(default_attributes)
  end

  it "uses the canonical scanner include paths" do
    expect(described_class.new.scanner_include).to eq(scanner_include)
  end

  it "uses the canonical scanner exclude paths" do
    expect(described_class.new.scanner_exclude).to eq(scanner_exclude)
  end

  it "yields the process configuration for host app setup" do
    RubySage.configure do |config|
      config.provider = :openai
      config.api_key = "test-key"
    end

    expect(RubySage.configuration).to have_attributes(provider: :openai, api_key: "test-key")
  end

  it "resets configuration to defaults" do
    RubySage.configure { |config| config.provider = :openai }

    RubySage.reset_configuration!

    expect(RubySage.configuration).to have_attributes(provider: :anthropic, api_key: nil)
  end
end
