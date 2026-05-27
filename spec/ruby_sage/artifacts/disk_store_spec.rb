# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe RubySage::Artifacts::DiskStore do
  let(:host_root) { Pathname(Dir.mktmpdir("ruby_sage_disk_store_")) }
  let(:store) { described_class.new(host_root: host_root) }

  after { FileUtils.remove_entry(host_root) if host_root.directory? }

  describe "#ensure_layout" do
    it "creates the .ruby_sage tree and a default .gitignore" do
      store.ensure_layout

      expect(host_root.join(".ruby_sage", "artifacts")).to be_directory
      expect(host_root.join(".ruby_sage", ".gitignore")).to be_file
    end

    it "leaves an existing .gitignore alone" do
      FileUtils.mkdir_p(host_root.join(".ruby_sage"))
      File.write(host_root.join(".ruby_sage", ".gitignore"), "# host override\n")

      store.ensure_layout

      expect(host_root.join(".ruby_sage", ".gitignore").read).to eq("# host override\n")
    end
  end

  describe "#write_artifact / #read_artifact" do
    let(:attributes) do
      {
        kind: "model",
        digest: "abc123",
        summary: "User aggregate root.",
        signature: { classes: [{ name: "User" }], methods: [{ name: "active?" }] },
        public_symbols: %w[User active? recent],
        route_mappings: nil,
        audiences: %i[developer admin]
      }
    end
    let(:serialized_signature) do
      {
        "classes" => [{ "name" => "User" }],
        "methods" => [{ "name" => "active?" }]
      }
    end

    it "writes a yaml file mirroring the host file tree" do
      store.write_artifact(path: "app/models/user.rb", attributes: attributes)

      expect(host_root.join(".ruby_sage/artifacts/app/models/user.rb.yml")).to be_file
    end

    it "round-trips attributes through disk" do
      store.write_artifact(path: "app/models/user.rb", attributes: attributes)
      loaded = store.read_artifact(path: "app/models/user.rb")

      expect(loaded).to include(
        schema_version: described_class::SCHEMA_VERSION,
        path: "app/models/user.rb",
        kind: "model",
        digest: "abc123",
        summary: "User aggregate root.",
        signature: serialized_signature,
        public_symbols: %w[User active? recent],
        route_mappings: nil,
        audiences: %w[developer admin]
      )
    end

    it "returns nil for unknown paths" do
      expect(store.read_artifact(path: "no/such/file.rb")).to be_nil
    end

    it "rejects absolute or parent-traversing paths" do
      expect { store.write_artifact(path: "/etc/passwd", attributes: attributes) }
        .to raise_error(ArgumentError)
      expect { store.write_artifact(path: "../escape.rb", attributes: attributes) }
        .to raise_error(ArgumentError)
    end
  end

  describe "#delete_artifact" do
    it "removes an existing file and returns true" do
      store.write_artifact(path: "app/models/post.rb", attributes: { digest: "x" })

      expect(store.delete_artifact(path: "app/models/post.rb")).to be(true)
      expect(host_root.join(".ruby_sage/artifacts/app/models/post.rb.yml")).not_to exist
    end

    it "returns false when nothing was removed" do
      expect(store.delete_artifact(path: "app/models/missing.rb")).to be(false)
    end
  end

  describe "#each_artifact / #artifact_paths" do
    before do
      store.write_artifact(path: "app/models/user.rb", attributes: { digest: "u" })
      store.write_artifact(path: "app/controllers/posts_controller.rb", attributes: { digest: "p" })
    end

    it "lists every artifact path on disk, sorted" do
      expect(store.artifact_paths).to eq(
        %w[app/controllers/posts_controller.rb app/models/user.rb]
      )
    end

    it "yields each artifact payload" do
      digests = store.each_artifact.map { |payload| payload.fetch(:digest) }

      expect(digests).to contain_exactly("u", "p")
    end

    it "returns an enumerator when no block is given" do
      expect(store.each_artifact).to be_a(Enumerator)
    end
  end

  describe "#prune_artifacts_outside" do
    before do
      store.write_artifact(path: "app/models/user.rb", attributes: { digest: "u" })
      store.write_artifact(path: "app/models/legacy.rb", attributes: { digest: "l" })
      store.write_artifact(path: "app/controllers/old/posts_controller.rb",
                           attributes: { digest: "p" })
    end

    it "removes files not in the kept set" do
      deleted = store.prune_artifacts_outside(["app/models/user.rb"])

      expect(deleted).to eq(2)
      expect(store.artifact_paths).to eq(["app/models/user.rb"])
    end

    it "removes the now-empty directories" do
      store.prune_artifacts_outside(["app/models/user.rb"])

      expect(host_root.join(".ruby_sage/artifacts/app/controllers")).not_to exist
    end
  end

  describe "#write_manifest / #read_manifest" do
    let(:started_at) { Time.utc(2026, 5, 27, 14, 0, 0) }
    let(:finished_at) { Time.utc(2026, 5, 27, 14, 0, 12) }

    let(:manifest_attributes) do
      {
        git_sha: "deadbeef",
        ruby_version: "3.3.0",
        rails_version: "7.1.0",
        started_at: started_at,
        finished_at: finished_at,
        file_count: 42,
        scanner: { "include" => ["app"], "exclude" => ["tmp/"] }
      }
    end

    it "serializes core fields with ISO-8601 timestamps" do
      store.write_manifest(attributes: manifest_attributes)

      expect(store.read_manifest).to include(
        schema_version: described_class::SCHEMA_VERSION,
        git_sha: "deadbeef",
        ruby_version: "3.3.0",
        rails_version: "7.1.0",
        started_at: "2026-05-27T14:00:00Z",
        finished_at: "2026-05-27T14:00:12Z",
        file_count: 42
      )
    end

    it "preserves the scanner config as-is" do
      store.write_manifest(attributes: manifest_attributes)

      expect(store.read_manifest[:scanner]).to eq(
        "include" => ["app"], "exclude" => ["tmp/"]
      )
    end

    it "returns nil when no manifest has been written" do
      expect(store.read_manifest).to be_nil
    end
  end
end
