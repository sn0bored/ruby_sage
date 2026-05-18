# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::KnowledgeChunk do
  after { described_class.delete_all }

  it "auto-assigns a slug from the title on create" do
    chunk = described_class.create!(title: "How to Export the Monthly Report", body: "Steps.")
    expect(chunk.slug).to eq("how-to-export-the-monthly-report")
  end

  it "rejects slugs with invalid characters" do
    chunk = described_class.new(title: "x", body: "y", slug: "Bad Slug!")
    expect(chunk).not_to be_valid
    expect(chunk.errors[:slug]).to be_present
  end

  it "rejects unknown audience values" do
    chunk = described_class.new(title: "x", body: "y", audiences: %w[admin alien])
    expect(chunk).not_to be_valid
    expect(chunk.errors[:audiences].join).to include("alien")
  end

  it "defaults audiences to an empty array" do
    chunk = described_class.create!(title: "x", body: "y")
    expect(chunk.audiences).to eq([])
  end

  it "auto-assigns a position one beyond the current max" do
    described_class.create!(title: "first", body: ".", position: 5)
    second = described_class.create!(title: "second", body: ".")
    expect(second.position).to eq(6)
  end

  describe "#visible_in_mode?" do
    it "is true when audiences include the mode" do
      chunk = described_class.create!(title: "x", body: ".", audiences: %w[admin])
      expect(chunk.visible_in_mode?(:admin)).to be(true)
      expect(chunk.visible_in_mode?(:user)).to be(false)
    end

    it "is true for any mode when audiences is empty" do
      chunk = described_class.create!(title: "x", body: ".", audiences: [])
      %i[developer admin user].each { |m| expect(chunk.visible_in_mode?(m)).to be(true) }
    end
  end

  describe "#move_up / #move_down" do
    it "swaps positions with adjacent rows" do
      first = described_class.create!(title: "first", body: ".", position: 1)
      second = described_class.create!(title: "second", body: ".", position: 2)

      second.move_up

      expect(first.reload.position).to eq(2)
      expect(second.reload.position).to eq(1)
    end

    it "is a no-op when already at the top" do
      only = described_class.create!(title: "only", body: ".", position: 1)
      expect { only.move_up }.not_to(change { only.reload.position })
    end
  end

  it "uses slug as to_param for friendly URLs" do
    chunk = described_class.create!(title: "Test Entry", body: ".")
    expect(chunk.to_param).to eq("test-entry")
  end
end
