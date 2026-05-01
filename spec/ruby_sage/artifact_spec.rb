# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::Artifact do
  let(:scan) { RubySage::Scan.create!(status: "completed") }
  let(:route_mappings) { [{ path: "/posts", controller: "posts#index" }] }
  let(:serialized_routes) { [{ "path" => "/posts", "controller" => "posts#index" }] }
  let(:artifact_attributes) do
    {
      scan: scan,
      path: "config/routes.rb",
      digest: "abc",
      public_symbols: ["PostsController"],
      route_mappings: route_mappings
    }
  end

  after do
    described_class.delete_all
    RubySage::Scan.delete_all
  end

  it "validates required metadata" do
    artifact = described_class.new(scan: scan)

    expect(artifact).not_to be_valid
  end

  it "serializes JSON array fields" do
    artifact = described_class.create!(artifact_attributes)

    expect(artifact.reload).to have_attributes(
      public_symbols: ["PostsController"],
      route_mappings: serialized_routes
    )
  end

  it "filters by kind" do
    described_class.create!(scan: scan, path: "app/models/post.rb", kind: "model", digest: "abc")

    expect(described_class.of_kind("model").pluck(:path)).to eq(["app/models/post.rb"])
  end
end
