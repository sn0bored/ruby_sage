# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::Scan do
  after do
    RubySage::Artifact.delete_all
    described_class.delete_all
  end

  it "validates known statuses" do
    scan = described_class.new(status: "unknown")

    expect(scan).not_to be_valid
  end

  it "orders latest completed scans by finish time" do
    older = described_class.create!(status: "completed", finished_at: 2.days.ago)
    newer = described_class.create!(status: "completed", finished_at: 1.day.ago)

    expect(described_class.latest_completed).to eq([newer, older])
  end

  it "destroys associated artifacts" do
    scan = described_class.create!(status: "completed")
    RubySage::Artifact.create!(scan: scan, path: "app/models/post.rb", digest: "abc")

    expect { scan.destroy! }.to change(RubySage::Artifact, :count).by(-1)
  end
end
