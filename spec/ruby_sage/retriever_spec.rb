# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::Retriever do
  before do
    RubySage::Artifact.delete_all
    RubySage::Scan.delete_all
  end

  after do
    RubySage::Artifact.delete_all
    RubySage::Scan.delete_all
  end

  it "returns an empty result when no completed scan exists" do
    result = described_class.new.call(query: "posts")

    expect(result).to eq(artifacts: [], citations: [], scan_id: nil)
  end

  it "tokenizes query text" do
    retriever = described_class.new(scan: completed_scan)

    tokens = retriever.send(:tokenize, "The Donor is in a UI, to Posts!")

    expect(tokens).to eq(%w[donor ui posts])
  end

  it "scores artifacts by summary, public symbols, and path matches" do
    scan = completed_scan
    create_donor_artifact(scan)
    create_posts_controller_artifact(scan, summary: "Lists posts.")

    result = described_class.new(scan: scan).call(query: "donor matching posts")

    expect(result[:citations].pluck(:path)).to eq(
      ["app/services/donor_matcher.rb", "app/controllers/posts_controller.rb"]
    )
  end

  it "applies page context boost when a route resolves" do
    scan = completed_scan
    create_posts_controller_artifact(scan, summary: "Posts index page.")

    result = retrieve(scan, query: "posts", page_context: { url: "https://example.com/posts" })

    expect(result[:citations].first).to include(path: "app/controllers/posts_controller.rb", score: 11.25)
  end

  it "sorts descending and respects the limit" do
    scan = completed_scan
    create_artifact(scan, path: "app/models/post.rb", summary: "Posts.", public_symbols: ["Post"])
    create_posts_controller_artifact(scan, summary: "Posts controller lists posts.")

    result = described_class.new(scan: scan, limit: 1).call(query: "posts")

    expect(result[:artifacts].map(&:path)).to eq(["app/controllers/posts_controller.rb"])
  end

  it "returns citations with the expected shape" do
    scan = completed_scan
    create_donor_artifact(scan, summary: "DonorMatcher pairs incoming donations. Extra detail.")

    result = described_class.new(scan: scan).call(query: "donor")

    expect(result[:citations].first).to eq(donor_citation)
  end

  describe "audience scoping" do
    it "excludes artifacts whose audiences do not include the requested mode" do
      scan = completed_scan
      create_artifact(scan, path: "app/services/billing.rb", kind: "service",
                            summary: "Billing service handles charges.", public_symbols: ["Billing"],
                            audiences: %w[developer])
      create_artifact(scan, path: "app/views/help/billing.html.erb", kind: "view",
                            summary: "Billing help page guides users.", public_symbols: [],
                            audiences: %w[developer admin user])

      developer = described_class.new(scan: scan, mode: :developer).call(query: "billing help")
      user = described_class.new(scan: scan, mode: :user).call(query: "billing help")

      expect(developer[:citations].pluck(:path)).to include(
        "app/services/billing.rb", "app/views/help/billing.html.erb"
      )
      expect(user[:citations].pluck(:path)).to eq(["app/views/help/billing.html.erb"])
    end

    it "treats artifacts with no audiences as visible in every mode (backwards compat)" do
      scan = completed_scan
      create_artifact(scan, path: "app/legacy.rb", kind: "other",
                            summary: "Legacy file.", public_symbols: ["Legacy"], audiences: nil)

      result = described_class.new(scan: scan, mode: :user).call(query: "legacy")

      expect(result[:citations].pluck(:path)).to eq(["app/legacy.rb"])
    end
  end

  def completed_scan
    RubySage::Scan.create!(status: "completed", finished_at: Time.current)
  end

  def create_artifact(scan, attributes)
    defaults = {
      scan: scan,
      digest: SecureRandom.hex(8),
      kind: "other",
      summary: nil,
      public_symbols: []
    }

    RubySage::Artifact.create!(defaults.merge(attributes))
  end

  def create_donor_artifact(scan, attributes = {})
    defaults = {
      path: "app/services/donor_matcher.rb",
      kind: "service",
      summary: "Donor matching pairs donations.",
      public_symbols: ["DonorMatcher"]
    }
    create_artifact(scan, defaults.merge(attributes))
  end

  def create_posts_controller_artifact(scan, attributes = {})
    defaults = {
      path: "app/controllers/posts_controller.rb",
      kind: "controller",
      public_symbols: ["PostsController"]
    }
    create_artifact(scan, defaults.merge(attributes))
  end

  def retrieve(scan, options)
    described_class.new(scan: scan).call(**options)
  end

  def donor_citation
    {
      path: "app/services/donor_matcher.rb",
      kind: "service",
      score: 4.5,
      snippet: "DonorMatcher pairs incoming donations."
    }
  end
end
