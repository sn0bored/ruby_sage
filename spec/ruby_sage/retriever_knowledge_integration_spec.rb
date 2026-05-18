# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::Retriever, "knowledge integration" do
  before do
    RubySage::KnowledgeChunk.delete_all
    RubySage::Artifact.delete_all
    RubySage::Scan.delete_all
  end

  after do
    RubySage::KnowledgeChunk.delete_all
    RubySage::Artifact.delete_all
    RubySage::Scan.delete_all
  end

  it "returns knowledge chunks alongside artifacts when query matches" do
    scan = RubySage::Scan.create!(status: "completed", finished_at: Time.current)
    RubySage::Artifact.create!(scan: scan, path: "app/models/report.rb",
                               kind: "model", digest: "x", summary: "Report model.",
                               public_symbols: ["Report"])
    RubySage::KnowledgeChunk.create!(
      slug: "monthly-report", title: "Monthly report",
      body: "How to run the monthly report.", tags: ["report"]
    )

    result = described_class.new(scan: scan).call(query: "monthly report")

    expect(result[:knowledge].size).to eq(1)
    expect(result[:knowledge].first.slug).to eq("monthly-report")
    expect(result[:citations].first[:kind]).to eq("knowledge")
  end

  it "applies knowledge_boost so curated entries outrank artifacts" do
    scan = RubySage::Scan.create!(status: "completed", finished_at: Time.current)
    RubySage::Artifact.create!(scan: scan, path: "app/services/foo.rb",
                               kind: "service", digest: "x",
                               summary: "foo bar baz", public_symbols: ["Foo"])
    RubySage::KnowledgeChunk.create!(slug: "foo-howto", title: "Foo",
                                     body: "Curated foo answer.", tags: ["foo"])

    result = described_class.new(scan: scan).call(query: "foo")

    expect(result[:citations].first[:kind]).to eq("knowledge")
  end

  it "filters knowledge by audience for the configured mode" do
    scan = RubySage::Scan.create!(status: "completed", finished_at: Time.current)
    RubySage::KnowledgeChunk.create!(slug: "admin-only", title: "Admin",
                                     body: "admin only content", audiences: %w[admin])
    RubySage::KnowledgeChunk.create!(slug: "everyone", title: "Everyone",
                                     body: "everyone content", audiences: %w[admin user])

    user_result = described_class.new(scan: scan, mode: :user).call(query: "content")
    admin_result = described_class.new(scan: scan, mode: :admin).call(query: "content")

    expect(user_result[:knowledge].map(&:slug)).to eq(["everyone"])
    expect(admin_result[:knowledge].map(&:slug)).to contain_exactly("admin-only", "everyone")
  end

  it "skips unpublished chunks" do
    scan = RubySage::Scan.create!(status: "completed", finished_at: Time.current)
    RubySage::KnowledgeChunk.create!(slug: "draft", title: "Draft",
                                     body: "drafty content", published: false)

    result = described_class.new(scan: scan).call(query: "drafty")

    expect(result[:knowledge]).to be_empty
  end
end
