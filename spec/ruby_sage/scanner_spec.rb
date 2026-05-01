# frozen_string_literal: true

require "digest"
require "rails_helper"

RSpec.describe RubySage::Scanner do
  let(:host_root) { Rails.root.join("../fixtures/scanner_app").expand_path }
  let(:config) do
    RubySage::Configuration.new.tap do |configuration|
      configuration.api_key = nil
      configuration.scanner_include = %w[app config db tmp log]
      configuration.scanner_exclude = ["tmp/", "log/", "config/credentials*"]
      configuration.scan_retention = 2
    end
  end

  after do
    FileUtils.rm_f(host_root.join("tmp/ruby_sage.lock"))
    RubySage::Artifact.delete_all
    RubySage::Scan.delete_all
  end

  it "walks include paths and skips excluded files" do
    scan = described_class.new(host_root: host_root, config: config).run

    expect(scan.artifacts.order(:path).pluck(:path)).to contain_exactly(
      "app/controllers/posts_controller.rb", "app/models/post.rb", "config/database.yml",
      "config/routes.rb", "db/schema.rb"
    )
  end

  it "classifies artifacts by relative path" do
    described_class.new(host_root: host_root, config: config).run
    kinds = RubySage::Artifact.pluck(:path, :kind).to_h

    expect(kinds).to include("app/models/post.rb" => "model", "config/routes.rb" => "routes")
  end

  it "stores stable digests from redacted contents" do
    described_class.new(host_root: host_root, config: config).run
    artifact = RubySage::Artifact.find_by!(path: "config/database.yml")
    sanitized = RubySage::SecretRedactor.new(host_root.join("config/database.yml").read).call

    expect(artifact.digest).to eq(Digest::SHA256.hexdigest(sanitized))
  end

  it "extracts public class and method symbols" do
    described_class.new(host_root: host_root, config: config).run
    artifact = RubySage::Artifact.find_by!(path: "app/models/post.rb")

    expect(artifact.public_symbols).to include("Post", "published?", "recent")
  end

  it "reuses summaries when digest and path are unchanged" do
    first = described_class.new(host_root: host_root, config: config).run
    first.artifacts.find_by!(path: "app/models/post.rb").update!(summary: "Cached")

    second = described_class.new(host_root: host_root, config: config).run

    expect(second.artifacts.find_by!(path: "app/models/post.rb").summary).to eq("Cached")
  end
end
