# frozen_string_literal: true

require "digest"
require "rails_helper"

RSpec.describe RubySage::Scanner do
  let(:host_root) { Rails.root.join("../fixtures/scanner_app").expand_path }
  let(:disk_root) { host_root.join(".ruby_sage") }
  let(:summary_provider) do
    Class.new do
      attr_reader :last_request

      def chat(system_prompt:, cached_context:, messages:, tools: nil)
        @last_request = {
          system_prompt: system_prompt,
          cached_context: cached_context,
          messages: messages,
          tools: tools
        }
        { answer: "Post model summary" }
      end
    end.new
  end
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
    FileUtils.rm_rf(disk_root)
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

  describe "disk artifacts" do
    it "writes a manifest and one artifact yml per file" do
      described_class.new(host_root: host_root, config: config).run

      expect(disk_root.join("manifest.json")).to be_file
      expect(disk_root.join("artifacts/app/models/post.rb.yml")).to be_file
      expect(disk_root.join("artifacts/config/routes.rb.yml")).to be_file
    end

    it "round-trips through the Indexer back to a Scan" do
      described_class.new(host_root: host_root, config: config).run
      RubySage::Artifact.delete_all
      RubySage::Scan.delete_all

      scan = RubySage::Indexer.new(host_root: host_root).run

      expect(scan.artifacts.pluck(:path)).to include(
        "app/models/post.rb", "config/routes.rb"
      )
    end

    it "does not create artifact rows before indexing from disk" do
      disk_store = Class.new(RubySage::Artifacts::DiskStore) do
        attr_reader :artifact_count_before_index

        def read_manifest
          @artifact_count_before_index = RubySage::Artifact.count
          super
        end
      end.new(host_root: host_root)

      described_class.new(host_root: host_root, config: config, disk_store: disk_store).run

      expect(disk_store.artifact_count_before_index).to eq(0)
    end

    it "writes summaries back to artifact yml before indexing" do
      allow(RubySage).to receive(:provider).and_return(summary_provider)
      config.api_key = "test-key"

      described_class.new(host_root: host_root, config: config).run

      payload = YAML.safe_load(disk_root.join("artifacts/app/models/post.rb.yml").read)
      expect(payload["summary"]).to eq("Post model summary")
    end
  end
end
