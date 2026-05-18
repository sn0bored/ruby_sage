# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe RubySage::Knowledge::Loader do
  it "returns [] when the path does not exist" do
    expect(described_class.new(path: "/nonexistent/path/xyz").load).to eq([])
  end

  it "loads entries from each YAML file in the directory" do
    Dir.mktmpdir do |dir|
      write_yaml(dir, "a.yml", "- slug: alpha\n  title: Alpha\n  body: First.\n")
      write_yaml(dir, "b.yml", "- slug: bravo\n  title: Bravo\n  body: Second.\n  audiences: [admin]\n")

      entries = described_class.new(path: dir).load

      expect(entries.map { |e| e["slug"] }).to contain_exactly("alpha", "bravo")
      expect(entries.find { |e| e["slug"] == "bravo" }["audiences"]).to eq(["admin"])
    end
  end

  def write_yaml(dir, name, contents)
    File.write(File.join(dir, name), contents)
  end

  it "accepts the entries-hash shape" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "c.yml"), <<~YAML)
        category: Reports
        entries:
          - slug: charlie
            title: Charlie
            body: Third.
      YAML

      entries = described_class.new(path: dir).load

      expect(entries.first["slug"]).to eq("charlie")
    end
  end

  it "raises InvalidFile when required keys are missing" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "bad.yml"), "- title: only-title\n")

      expect { described_class.new(path: dir).load }
        .to raise_error(RubySage::Knowledge::Loader::InvalidFile, /missing required keys/)
    end
  end

  it "raises InvalidFile on malformed YAML" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "broken.yml"), "this: is: not: valid:\n  - [")

      expect { described_class.new(path: dir).load }
        .to raise_error(RubySage::Knowledge::Loader::InvalidFile, /Could not parse/)
    end
  end
end
