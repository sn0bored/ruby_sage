# frozen_string_literal: true

require "json"
require "rails_helper"
require "rails/generators"
require "rails/generators/test_case"
require "generators/ruby_sage/install/install_generator"

RSpec.describe RubySage::Generators::InstallGenerator, type: :generator do
  destination = File.expand_path("../../../../../tmp/generator_destination", __dir__)

  before do
    FileUtils.rm_rf(destination)
    FileUtils.mkdir_p(destination)
    write_stub_rake(destination)
  end

  after do
    FileUtils.rm_rf(destination)
  end

  it "copies the configuration initializer" do
    run_generator(destination)

    initializer = File.join(destination, "config/initializers/ruby_sage.rb")
    expect(File).to exist(initializer)

    contents = File.read(initializer)
    expect(contents).to include("RubySage.configure")
    expect(contents).to include("ENV.fetch(\"ANTHROPIC_API_KEY\", nil)")
    expect(contents).to include("config.auth_check")
  end

  it "creates the disk artifact layout" do
    run_generator(destination)

    expect(File).to be_directory(File.join(destination, ".ruby_sage"))
    expect(File).to be_directory(File.join(destination, ".ruby_sage/artifacts"))
    expect(File).to exist(File.join(destination, ".ruby_sage/.gitignore"))
  end

  it "writes the Claude MCP server snippet" do
    run_generator(destination, "--with-claude-config")

    config = read_json(File.join(destination, ".claude.json"))
    expect(config.fetch("mcpServers").fetch("ruby_sage")).to eq(ruby_sage_mcp_server)
  end

  it "merges the Claude MCP server snippet without clobbering other servers" do
    File.write(
      File.join(destination, ".claude.json"),
      "#{JSON.pretty_generate(existing_claude_config)}\n"
    )

    run_generator(destination, "--with-claude-config")

    servers = read_json(File.join(destination, ".claude.json")).fetch("mcpServers")
    expect(servers.fetch("ruby_sage")).to eq(ruby_sage_mcp_server)
    expect(servers.fetch("other_agent")).to eq(existing_claude_config.fetch("mcpServers").fetch("other_agent"))
  end

  def run_generator(destination, *args)
    silence_stdout do
      described_class.start(args, destination_root: destination)
    end
  end

  def write_stub_rake(destination)
    rake_path = File.join(destination, "bin/rake")
    FileUtils.mkdir_p(File.dirname(rake_path))
    File.write(rake_path, "#!/usr/bin/env ruby\nexit 0\n")
    FileUtils.chmod(0o755, rake_path)
  end

  def read_json(path)
    JSON.parse(File.read(path))
  end

  def ruby_sage_mcp_server
    {
      "command" => "bundle",
      "args" => ["exec", "ruby_sage", "mcp", "--host-root", "."]
    }
  end

  def existing_claude_config
    {
      "theme" => "dark",
      "mcpServers" => {
        "other_agent" => {
          "command" => "other",
          "args" => ["serve"]
        }
      }
    }
  end

  def silence_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end
end
