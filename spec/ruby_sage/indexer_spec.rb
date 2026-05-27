# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe RubySage::Indexer do
  let(:host_root) { Pathname(Dir.mktmpdir("ruby_sage_indexer_")) }
  let(:disk_store) { RubySage::Artifacts::DiskStore.new(host_root: host_root) }

  after do
    FileUtils.remove_entry(host_root) if host_root.directory?
    RubySage::Artifact.delete_all
    RubySage::Scan.delete_all
  end

  context "with a manifest and two artifacts on disk" do
    let(:started_at) { Time.utc(2026, 5, 27, 14, 0, 0) }
    let(:finished_at) { Time.utc(2026, 5, 27, 14, 0, 30) }

    before do
      disk_store.write_manifest(
        attributes: {
          git_sha: "abc123",
          ruby_version: "3.3.0",
          rails_version: "7.1.0",
          started_at: started_at,
          finished_at: finished_at,
          file_count: 2,
          scanner: { "include" => ["app"] }
        }
      )
      disk_store.write_artifact(
        path: "app/models/user.rb",
        attributes: {
          kind: "model",
          digest: "u-digest",
          summary: "User aggregate",
          signature: {
            classes: [{ name: "User", superclass: "ApplicationRecord" }],
            methods: [{ name: "active?", receiver: "instance" }]
          },
          public_symbols: %w[User active?],
          audiences: %w[developer]
        }
      )
      disk_store.write_artifact(
        path: "config/routes.rb",
        attributes: {
          kind: "routes",
          digest: "r-digest",
          summary: nil,
          public_symbols: [],
          audiences: %w[developer admin]
        }
      )
    end

    it "creates a single completed Scan with manifest metadata" do
      scan = described_class.new(host_root: host_root).run

      expect(scan).to have_attributes(
        status: "completed",
        git_sha: "abc123",
        ruby_version: "3.3.0",
        rails_version: "7.1.0",
        file_count: 2
      )
    end

    it "creates one Artifact row per disk artifact" do
      scan = described_class.new(host_root: host_root).run

      expect(scan.artifacts.pluck(:path)).to contain_exactly(
        "app/models/user.rb", "config/routes.rb"
      )
    end

    it "round-trips artifact payloads into the DB" do
      scan = described_class.new(host_root: host_root).run
      user_artifact = scan.artifacts.find_by!(path: "app/models/user.rb")

      expect(user_artifact).to have_attributes(
        kind: "model",
        digest: "u-digest",
        summary: "User aggregate",
        signature: {
          "classes" => [{ "name" => "User", "superclass" => "ApplicationRecord" }],
          "methods" => [{ "name" => "active?", "receiver" => "instance" }]
        },
        public_symbols: %w[User active?],
        audiences: %w[developer]
      )
    end
  end

  it "raises MissingManifest when nothing has been scanned" do
    expect { described_class.new(host_root: host_root).run }
      .to raise_error(described_class::MissingManifest)
  end
end
