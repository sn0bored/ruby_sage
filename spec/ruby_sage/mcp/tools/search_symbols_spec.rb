# frozen_string_literal: true

require "spec_helper"
require "ruby_sage/mcp/tools/search_symbols"

require_relative "../fixture_helper"

RSpec.describe RubySage::MCP::Tools::SearchSymbols do
  include RubySageMcpFixtureHelper

  let(:host_root) { build_mcp_fixture }
  let(:tool) { described_class.new(host_root: host_root, disk_store: disk_store(host_root)) }

  after { remove_mcp_fixture(host_root) }

  it "returns exact class matches" do
    result = tool.call("name" => "User", "kind" => "class")

    expect(result).to eq(
      [{ "path" => "app/models/user.rb", "kind" => "class", "symbol" => "User" }]
    )
  end

  it "returns exact method matches" do
    result = tool.call("name" => "active?", "kind" => "method")

    expect(result).to eq(
      [{ "path" => "app/models/user.rb", "kind" => "method", "symbol" => "active?" }]
    )
  end

  it "does not return substring matches" do
    expect(tool.call("name" => "active", "kind" => "any")).to eq([])
  end
end
