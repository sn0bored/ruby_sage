# frozen_string_literal: true

require "spec_helper"
require "ruby_sage/mcp/tools/get_file_context"

require_relative "../fixture_helper"

RSpec.describe RubySage::MCP::Tools::GetFileContext do
  include RubySageMcpFixtureHelper

  let(:host_root) { build_mcp_fixture }
  let(:tool) { described_class.new(host_root: host_root, disk_store: disk_store(host_root)) }

  after { remove_mcp_fixture(host_root) }

  it "returns compact signature text by default" do
    result = tool.call("path" => "app/models/user.rb")

    expect(result).to include("Classes:\n- User < ApplicationRecord")
    expect(result).to include("Methods:\n- instance public active?(limit:)")
    expect(result).to include("Constants:\n- MAX_LOGIN_ATTEMPTS")
  end

  it "returns full host file contents when requested" do
    result = tool.call("path" => "app/controllers/posts_controller.rb", "mode" => "full")

    expect(result).to include("class PostsController < ApplicationController")
  end

  it "rejects parent-traversing paths" do
    expect { tool.call("path" => "../secrets.yml", "mode" => "full") }
      .to raise_error(ArgumentError, /host-relative/)
  end
end
