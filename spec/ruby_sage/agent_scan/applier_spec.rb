# frozen_string_literal: true

require "json"
require "rails_helper"

RSpec.describe RubySage::AgentScan::Applier do
  let(:tmp_dir) { Rails.root.join("../tmp/agent_scan_applier_spec").expand_path }
  let(:manifest_path) { tmp_dir.join("manifest.json") }
  let(:summaries_path) { tmp_dir.join("summaries.json") }

  before do
    FileUtils.mkdir_p(tmp_dir)
  end

  after do
    FileUtils.rm_rf(tmp_dir)
    RubySage::Artifact.delete_all
    RubySage::Scan.delete_all
  end

  def write_manifest(files:)
    payload = {
      "schema_version" => 1,
      "generated_at" => Time.now.utc.iso8601,
      "git_sha" => "abc123",
      "ruby_version" => "3.4.7",
      "rails_version" => "8.0.3",
      "summary_system_prompt" => "...",
      "files" => files
    }
    File.write(manifest_path, JSON.generate(payload))
  end

  def write_summaries(summaries:)
    payload = { "schema_version" => 1, "summaries" => summaries }
    File.write(summaries_path, JSON.generate(payload))
  end

  it "creates a completed scan with one artifact per manifest entry" do
    write_manifest(files: [
                     {
                       "path" => "app/models/user.rb", "kind" => "model",
                       "digest" => "deadbeef" * 8, "public_symbols" => %w[User],
                       "redacted_contents" => "class User; end", "previous_summary" => nil,
                       "needs_summary" => true
                     }
                   ])
    write_summaries(summaries: { "app/models/user.rb" => "User model summary" })

    scan = described_class.new(manifest_path: manifest_path, summaries_path: summaries_path).run

    expect(scan).to be_persisted
    expect(scan.status).to eq("completed")
    expect(scan.file_count).to eq(1)
    expect(scan.artifacts.count).to eq(1)
    expect(scan.artifacts.first.summary).to eq("User model summary")
  end

  it "falls back to previous_summary when the agent did not provide one" do
    write_manifest(files: [
                     {
                       "path" => "app/models/post.rb", "kind" => "model",
                       "digest" => "cafef00d" * 8, "public_symbols" => %w[Post],
                       "redacted_contents" => "class Post; end",
                       "previous_summary" => "Cached Post summary", "needs_summary" => false
                     }
                   ])
    write_summaries(summaries: {})

    scan = described_class.new(manifest_path: manifest_path, summaries_path: summaries_path).run

    expect(scan.artifacts.first.summary).to eq("Cached Post summary")
  end

  it "treats blank agent summaries as missing and falls back" do
    write_manifest(files: [
                     {
                       "path" => "app/models/post.rb", "kind" => "model",
                       "digest" => "cafef00d" * 8, "public_symbols" => %w[Post],
                       "redacted_contents" => "class Post; end",
                       "previous_summary" => "Cached", "needs_summary" => false
                     }
                   ])
    write_summaries(summaries: { "app/models/post.rb" => "   " })

    scan = described_class.new(manifest_path: manifest_path, summaries_path: summaries_path).run

    expect(scan.artifacts.first.summary).to eq("Cached")
  end

  it "is a no-op on partial failures - no scan if any artifact insert raises" do
    write_manifest(files: [
                     { "path" => "app/models/a.rb", "kind" => "model", "digest" => "a" * 64,
                       "public_symbols" => [], "redacted_contents" => "", "previous_summary" => nil,
                       "needs_summary" => true },
                     { "path" => nil, "kind" => "model", "digest" => "b" * 64,
                       "public_symbols" => [], "redacted_contents" => "", "previous_summary" => nil,
                       "needs_summary" => true }
                   ])
    write_summaries(summaries: {})

    expect do
      described_class.new(manifest_path: manifest_path, summaries_path: summaries_path).run
    end.to raise_error(ActiveRecord::RecordInvalid)

    expect(RubySage::Scan.count).to eq(0)
    expect(RubySage::Artifact.count).to eq(0)
  end

  it "raises InvalidManifest when the manifest is missing" do
    write_summaries(summaries: {})

    expect do
      described_class.new(manifest_path: tmp_dir.join("nope.json"), summaries_path: summaries_path).run
    end.to raise_error(described_class::InvalidManifest, /not found/)
  end

  it "raises InvalidManifest when the schema version is unsupported" do
    File.write(manifest_path, JSON.generate("schema_version" => 99, "files" => []))
    write_summaries(summaries: {})

    expect do
      described_class.new(manifest_path: manifest_path, summaries_path: summaries_path).run
    end.to raise_error(described_class::InvalidManifest, /schema_version/)
  end

  it "tolerates a missing summaries file by falling back to previous_summary" do
    write_manifest(files: [
                     {
                       "path" => "app/models/post.rb", "kind" => "model",
                       "digest" => "cafef00d" * 8, "public_symbols" => %w[Post],
                       "redacted_contents" => "class Post; end",
                       "previous_summary" => "Cached", "needs_summary" => false
                     }
                   ])

    scan = described_class.new(manifest_path: manifest_path, summaries_path: summaries_path).run

    expect(scan.artifacts.first.summary).to eq("Cached")
  end
end
