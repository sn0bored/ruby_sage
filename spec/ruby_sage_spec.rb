# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage do
  before do
    RubySage::Artifact.delete_all
    RubySage::Scan.delete_all
  end

  after do
    RubySage::Artifact.delete_all
    RubySage::Scan.delete_all
  end

  it "has a version number" do
    expect(RubySage::VERSION).not_to be_nil
  end

  it "retrieves context through the convenience API" do
    scan = RubySage::Scan.create!(status: "completed", finished_at: Time.current)
    create_posts_artifact(scan)

    result = described_class.context_for("posts")

    expect(result[:citations].first[:path]).to eq("app/controllers/posts_controller.rb")
  end

  def create_posts_artifact(scan)
    RubySage::Artifact.create!(
      scan: scan,
      path: "app/controllers/posts_controller.rb",
      kind: "controller",
      digest: "abc",
      summary: "PostsController lists synthetic posts.",
      public_symbols: ["PostsController"]
    )
  end
end
