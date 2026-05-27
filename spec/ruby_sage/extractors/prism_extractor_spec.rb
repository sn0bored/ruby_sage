# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::Extractors::PrismExtractor do
  let(:fixture_root) { Rails.root.join("../fixtures/scanner_app/signatures").expand_path }

  def signature_for(filename)
    described_class.new(path: fixture_root.join(filename)).call
  end

  def expect_user_class(user_class)
    expect(user_class).to include(
      name: "User",
      superclass: "ApplicationRecord",
      ancestry: %w[User ApplicationRecord],
      includes: ["Searchable"],
      extends: ["ClassMethods"],
      prepends: ["Trackable"]
    )
  end

  def expect_active_method(active_method)
    expect(active_method).to include(receiver: "instance", arity: -2, visibility: "public")
    expect(active_method[:params]).to include(
      { name: "name", kind: "req" },
      { name: "opts", kind: "key" },
      { name: "extra", kind: "kwrest" }
    )
  end

  def expect_model_macros(active_record)
    expect(active_record[:associations]).to include(
      kind: "has_many",
      name: "posts",
      options: { dependent: "destroy" }
    )
    expect(active_record[:validations]).to include(
      kind: "presence",
      fields: ["email"],
      options: {}
    )
    expect(active_record[:validations]).to include(
      kind: "uniqueness",
      fields: ["email"],
      options: { case_sensitive: false }
    )
  end

  it "extracts a plain class signature" do
    signature = signature_for("plain_user.rb")
    user_class = signature[:classes].first
    active_method = signature[:methods].find { |method| method[:name] == "active?" }

    expect_user_class(user_class)
    expect_active_method(active_method)
    expect(signature[:constants]).to include("MAX_LENGTH")
  end

  it "extracts Active Record macros from a model" do
    signature = signature_for("account.rb")
    active_record = signature[:activerecord]

    expect_model_macros(active_record)
    expect(active_record[:enums]).to include(name: "status", values: %w[active archived])
    expect(active_record[:scopes]).to include(
      name: "active",
      params: [{ name: "limit", kind: "opt" }]
    )
  end

  it "extracts module signatures" do
    signature = signature_for("searchable.rb")
    searchable = signature[:classes].first

    expect(searchable).to include(
      name: "Searchable",
      superclass: nil,
      ancestry: ["Searchable"],
      extends: ["ActiveSupport::Concern"]
    )
    expect(signature[:methods]).to include(
      hash_including(name: "matches?", receiver: "instance", visibility: "public"),
      hash_including(name: "searchable?", receiver: "instance", visibility: "protected")
    )
  end

  it "extracts constants and methods from a file with no top-level class" do
    signature = signature_for("constants_only.rb")

    expect(signature[:classes]).to eq([])
    expect(signature[:constants]).to contain_exactly("DEFAULT_OPTIONS", "MAX_LENGTH")
    expect(signature[:methods]).to include(
      hash_including(name: "helper_name", receiver: "instance", arity: 1)
    )
  end
end
