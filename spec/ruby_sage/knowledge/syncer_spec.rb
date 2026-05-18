# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::Knowledge::Syncer do
  after { RubySage::KnowledgeChunk.delete_all }

  let(:entry) do
    {
      "slug" => "create-report",
      "title" => "Create the monthly report",
      "body" => "Steps to follow.",
      "audiences" => %w[admin],
      "tags" => %w[reports monthly]
    }
  end

  it "creates new entries on first run" do
    result = described_class.new(entries: [entry]).run

    expect(result.created).to eq(1)
    expect(result.updated).to eq(0)
    expect(RubySage::KnowledgeChunk.find_by(slug: "create-report").source).to eq("yaml")
  end

  it "is idempotent — unchanged input produces 0 updates" do
    described_class.new(entries: [entry]).run
    result = described_class.new(entries: [entry]).run

    expect(result).to have_attributes(created: 0, updated: 0, unchanged: 1)
  end

  it "updates existing yaml-sourced rows when content changes" do
    described_class.new(entries: [entry]).run
    revised = entry.merge("title" => "Create the *new* monthly report")

    result = described_class.new(entries: [revised]).run

    expect(result.updated).to eq(1)
    expect(RubySage::KnowledgeChunk.find_by(slug: "create-report").title).to include("*new*")
  end

  it "removes yaml-sourced rows whose slugs are no longer present" do
    described_class.new(entries: [entry]).run
    result = described_class.new(entries: []).run

    expect(result.removed).to eq(1)
    expect(RubySage::KnowledgeChunk.find_by(slug: "create-report")).to be_nil
  end

  it "never touches admin-authored rows even on slug collision" do
    admin_row = RubySage::KnowledgeChunk.create!(
      slug: "create-report", title: "Admin-authored", body: "Hand-written.",
      source: "admin_ui", audiences: ["admin"]
    )

    described_class.new(entries: [entry]).run

    admin_row.reload
    expect(admin_row.title).to eq("Admin-authored")
    expect(admin_row.source).to eq("admin_ui")
  end

  it "leaves admin rows in place when emptying the YAML directory" do
    RubySage::KnowledgeChunk.create!(
      slug: "admin-only", title: "Admin only", body: ".",
      source: "admin_ui"
    )

    described_class.new(entries: []).run

    expect(RubySage::KnowledgeChunk.find_by(slug: "admin-only")).to be_present
  end
end
