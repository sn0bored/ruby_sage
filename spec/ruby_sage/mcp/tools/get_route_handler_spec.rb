# frozen_string_literal: true

require "spec_helper"
require "ruby_sage/mcp/tools/get_route_handler"

require_relative "../fixture_helper"

RSpec.describe RubySage::MCP::Tools::GetRouteHandler do
  include RubySageMcpFixtureHelper

  let(:host_root) { build_mcp_fixture }
  let(:tool) { described_class.new(host_root: host_root, disk_store: disk_store(host_root)) }

  after { remove_mcp_fixture(host_root) }

  it "returns the handler for an exact route path" do
    result = tool.call("path" => "/posts")

    expect(result).to include(
      "verb" => "GET",
      "controller" => "PostsController",
      "action" => "index",
      "file" => "app/controllers/posts_controller.rb"
    )
  end

  it "matches dynamic route segments" do
    result = tool.call("path" => "/posts/42", "verb" => "GET")

    expect(result).to include("path" => "/posts/:id", "action" => "show")
  end

  it "returns nil for an unknown route" do
    expect(tool.call("path" => "/missing")).to be_nil
  end
end
