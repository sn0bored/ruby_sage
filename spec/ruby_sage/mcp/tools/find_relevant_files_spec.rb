# frozen_string_literal: true

require "spec_helper"
require "ruby_sage/mcp/tools/find_relevant_files"

require_relative "../fixture_helper"

RSpec.describe RubySage::MCP::Tools::FindRelevantFiles do
  include RubySageMcpFixtureHelper

  let(:host_root) { build_mcp_fixture }
  let(:tool) { described_class.new(host_root: host_root, disk_store: disk_store(host_root)) }

  after { remove_mcp_fixture(host_root) }

  it "ranks signature symbol hits with symbol reasons" do
    result = tool.call("query" => "User active")

    expect(result.first).to include("path" => "app/models/user.rb", "kind" => "model")
    expect(result.first["reasons"]).to include("symbol:User", "symbol:active?")
  end

  it "includes route reasons from routes.json" do
    result = tool.call("query" => "/posts", "max_results" => 2)
    controller = result.find { |hit| hit["path"] == "app/controllers/posts_controller.rb" }

    expect(controller["reasons"]).to include("route:/posts")
  end

  it "honors max_results" do
    result = tool.call("query" => "posts", "max_results" => 1)

    expect(result.length).to eq(1)
  end
end
