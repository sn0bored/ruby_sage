# frozen_string_literal: true

require "spec_helper"
require "ruby_sage/mcp/tools/index_status"

require_relative "../fixture_helper"

RSpec.describe RubySage::MCP::Tools::IndexStatus do
  include RubySageMcpFixtureHelper

  let(:host_root) { build_mcp_fixture }
  let(:tool) { described_class.new(host_root: host_root, disk_store: disk_store(host_root)) }

  after { remove_mcp_fixture(host_root) }

  it "returns manifest metadata and fresh status" do
    result = tool.call({})

    expect(result).to include(
      "git_sha" => "abc123",
      "ruby_version" => "3.1.2",
      "rails_version" => "7.1.0",
      "file_count" => 2,
      "finished_at" => "2026-05-27T12:00:30Z",
      "fresh" => true
    )
  end

  it "reports stale status when the manifest is missing" do
    missing_root = Pathname(Dir.mktmpdir("ruby_sage_mcp_missing_"))
    missing_tool = described_class.new(host_root: missing_root, disk_store: disk_store(missing_root))

    expect(missing_tool.call({})).to include("file_count" => 0, "fresh" => false)
  ensure
    remove_mcp_fixture(missing_root)
  end
end
