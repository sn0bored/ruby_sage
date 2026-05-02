# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::AgentScan::Instructions do
  let(:output_dir) { Pathname("/tmp/ruby_sage_instructions_spec") }
  let(:manifest) do
    {
      "summary_system_prompt" => "You are summarizing a single file...",
      "files" => [
        { "path" => "app/models/user.rb", "needs_summary" => true },
        { "path" => "app/models/post.rb", "needs_summary" => false }
      ]
    }
  end

  it "renders a markdown document with a header and how-to" do
    body = described_class.new(manifest: manifest, output_dir: output_dir).render

    expect(body).to start_with("# RubySage agent scan")
    expect(body).to include("How to run")
    expect(body).to include("Output format")
    expect(body).to include("summaries.json")
  end

  it "reports counts of files needing summaries vs cached" do
    body = described_class.new(manifest: manifest, output_dir: output_dir).render

    expect(body).to include("2 files in this scan. 1 need a")
    expect(body).to include("1 can reuse a cached summary")
  end

  it "embeds the summary system prompt verbatim" do
    body = described_class.new(manifest: manifest, output_dir: output_dir).render

    expect(body).to include("You are summarizing a single file")
  end

  it "names the output paths the agent should read and write" do
    body = described_class.new(manifest: manifest, output_dir: output_dir).render

    expect(body).to include(output_dir.join("manifest.json").to_s)
    expect(body).to include(output_dir.join("summaries.json").to_s)
  end
end
