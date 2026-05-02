# frozen_string_literal: true

require "json"
require "rails_helper"

RSpec.describe RubySage::AgentScan::Planner do
  let(:host_root) { Rails.root.join("../fixtures/scanner_app").expand_path }
  let(:output_dir) { Rails.root.join("../tmp/agent_scan_planner_spec").expand_path }
  let(:config) do
    RubySage::Configuration.new.tap do |configuration|
      configuration.api_key = nil
      configuration.scanner_include = %w[app config db]
      configuration.scanner_exclude = ["tmp/", "log/", "config/credentials*"]
    end
  end

  before do
    FileUtils.rm_rf(output_dir)
  end

  after do
    FileUtils.rm_rf(output_dir)
    RubySage::Artifact.delete_all
    RubySage::Scan.delete_all
  end

  it "writes a manifest plus instructions and reports counts" do
    result = described_class.new(host_root: host_root, config: config, output_dir: output_dir).run

    expect(File).to exist(result[:manifest_path])
    expect(File).to exist(result[:instructions_path])
    expect(result[:file_count]).to be > 0
    expect(result[:needs_summary_count]).to eq(result[:file_count])
  end

  it "embeds redacted contents and digest per file in the manifest" do
    described_class.new(host_root: host_root, config: config, output_dir: output_dir).run

    manifest = JSON.parse(File.read(File.join(output_dir, "manifest.json")))
    db_yml_entry = manifest["files"].find { |entry| entry["path"] == "config/database.yml" }

    expect(db_yml_entry).not_to be_nil
    expect(db_yml_entry["redacted_contents"]).to include("[REDACTED]")
    expect(db_yml_entry["digest"]).to match(/\A[a-f0-9]{64}\z/)
    expect(db_yml_entry["needs_summary"]).to be(true)
  end

  it "marks files with cached summaries as not needing a new summary" do
    seed_cached_summary("app/models/post.rb", "Cached Post summary")

    described_class.new(host_root: host_root, config: config, output_dir: output_dir).run
    manifest = JSON.parse(File.read(File.join(output_dir, "manifest.json")))
    post_entry = manifest["files"].find { |entry| entry["path"] == "app/models/post.rb" }

    expect(post_entry["needs_summary"]).to be(false)
    expect(post_entry["previous_summary"]).to eq("Cached Post summary")
  end

  def seed_cached_summary(relative_path, summary)
    sanitized = RubySage::SecretRedactor.new(host_root.join(relative_path).read).call
    seed_scan = RubySage::Scan.create!(
      status: "completed", started_at: Time.current, finished_at: Time.current,
      git_sha: "seed", ruby_version: RUBY_VERSION, rails_version: Rails::VERSION::STRING,
      file_count: 1
    )
    RubySage::Artifact.create!(
      scan: seed_scan, path: relative_path, kind: "model",
      digest: Digest::SHA256.hexdigest(sanitized), summary: summary,
      public_symbols: %w[Post], route_mappings: nil
    )
  end

  it "includes the summary system prompt verbatim so agents share the contract" do
    described_class.new(host_root: host_root, config: config, output_dir: output_dir).run

    manifest = JSON.parse(File.read(File.join(output_dir, "manifest.json")))
    expect(manifest["summary_system_prompt"]).to include("summarizing a single file")
  end

  it "tags each manifest entry with default audiences from the heuristic" do
    described_class.new(host_root: host_root, config: config, output_dir: output_dir).run
    manifest = JSON.parse(File.read(File.join(output_dir, "manifest.json")))

    by_path = manifest["files"].to_h { |entry| [entry["path"], entry["audiences"]] }
    expect(by_path["app/models/post.rb"]).to eq(%w[developer admin])
    expect(by_path["config/routes.rb"]).to eq(%w[developer])
    expect(by_path["app/controllers/posts_controller.rb"]).to eq(%w[developer admin])
  end

  it "defaults the output directory to tmp/ruby_sage under the host root" do
    default_dir = host_root.join("tmp/ruby_sage")
    FileUtils.rm_rf(default_dir)

    result = described_class.new(host_root: host_root, config: config).run

    expect(result[:manifest_path]).to start_with(default_dir.to_s)
  ensure
    FileUtils.rm_rf(default_dir)
  end
end
