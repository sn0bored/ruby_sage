# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "spec_helper"
require "stringio"
require "timeout"

require "ruby_sage/mcp/server"

require_relative "fixture_helper"

RSpec.describe RubySage::MCP::Server do
  include RubySageMcpFixtureHelper

  let(:host_root) { build_mcp_fixture }

  after { remove_mcp_fixture(host_root) }

  it "responds to the initialize handshake" do
    responses = run_server([{ "jsonrpc" => "2.0", "id" => 1, "method" => "initialize" }])

    expect(responses.first["id"]).to eq(1)
    expect(responses.first.dig("result", "capabilities", "tools")).to eq("listChanged" => false)
    expect(responses.first.dig("result", "serverInfo", "name")).to eq("ruby_sage")
  end

  it "lists tools with JSON schemas" do
    responses = run_server([{ "jsonrpc" => "2.0", "id" => 2, "method" => "tools/list" }])
    tools = responses.first.dig("result", "tools")

    names = tools.each_with_object([]) { |tool, list| list << tool["name"] }

    expect(names).to contain_exactly(
      "find_relevant_files", "get_file_context", "get_route_handler", "search_symbols", "index_status"
    )
    expect(tools).to all(include("inputSchema" => include("type" => "object")))
  end

  it "dispatches tools/call to a registered tool" do
    responses = run_server([tool_call_request("search_symbols", "name" => "User")])
    result = responses.first.dig("result", "structuredContent", "result")

    expect(result).to include("path" => "app/models/user.rb", "kind" => "class", "symbol" => "User")
  end

  it "uses newline-delimited JSON-RPC framing and ignores notifications" do
    responses = run_server(
      [
        { "jsonrpc" => "2.0", "method" => "notifications/initialized" },
        { "jsonrpc" => "2.0", "id" => 3, "method" => "tools/call", "params" => { "name" => "index_status" } }
      ]
    )

    expect(responses.length).to eq(1)
    expect(responses.first["id"]).to eq(3)
  end

  it "returns JSON-RPC parse errors for malformed input" do
    input = StringIO.new("{bad json}\n")
    output = StringIO.new

    described_class.new(host_root: host_root, input: input, output: output).run

    expect(parse_responses(output.string).first.dig("error", "code")).to eq(-32_700)
  end

  it "serves requests through the executable over stdio" do
    responses = run_executable(
      [
        { "jsonrpc" => "2.0", "id" => 1, "method" => "initialize" },
        tool_call_request("get_route_handler", "path" => "/posts")
      ]
    )

    expect(responses.first.dig("result", "serverInfo", "name")).to eq("ruby_sage")
    expect(responses.last.dig("result", "structuredContent", "result", "action")).to eq("index")
  end

  def run_server(requests)
    input = StringIO.new("#{requests.map { |request| JSON.generate(request) }.join("\n")}\n")
    output = StringIO.new
    described_class.new(host_root: host_root, input: input, output: output).run
    parse_responses(output.string)
  end

  def run_executable(requests)
    Timeout.timeout(5) do
      command = [RbConfig.ruby, executable_path, "mcp", "--host-root", host_root.to_s]
      Open3.popen3(*command) do |stdin, stdout, stderr, wait|
        stdin.write("#{requests.map { |request| JSON.generate(request) }.join("\n")}\n")
        stdin.close
        responses = parse_responses(stdout.read)
        raise stderr.read unless wait.value.success?

        responses
      end
    end
  end

  def executable_path
    File.expand_path("../../../exe/ruby_sage", __dir__)
  end

  def tool_call_request(name, arguments = {})
    {
      "jsonrpc" => "2.0",
      "id" => 10,
      "method" => "tools/call",
      "params" => {
        "name" => name,
        "arguments" => arguments
      }
    }
  end

  def parse_responses(output)
    output.lines.map { |line| JSON.parse(line) }
  end
end
