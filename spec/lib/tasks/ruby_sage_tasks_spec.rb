# frozen_string_literal: true

require "rails_helper"
require "rake"
require "stringio"

RSpec.describe "ruby_sage rake tasks" do
  let(:rake) { Rake::Application.new }

  before do
    Rake.application = rake
    Rake::Task.define_task(:environment)
    load Rails.root.join("../../lib/tasks/ruby_sage_tasks.rake").to_s
  end

  after do
    Rake.application = Rake::Application.new
  end

  describe "ruby_sage:export_artifacts and ruby_sage:import_artifacts" do
    it "round-trips a completed scan with its artifacts" do
      scan = RubySage::Scan.create!(
        status: "completed",
        git_sha: "abc123",
        ruby_version: "3.3.4",
        rails_version: "7.1.0",
        file_count: 2,
        started_at: 1.minute.ago,
        finished_at: Time.current
      )
      RubySage::Artifact.create!(
        scan: scan,
        path: "app/models/widget.rb",
        kind: "model",
        digest: "deadbeef",
        summary: "A synthetic widget model used in specs.",
        public_symbols: ["Widget"],
        route_mappings: nil
      )
      RubySage::Artifact.create!(
        scan: scan,
        path: "app/controllers/widgets_controller.rb",
        kind: "controller",
        digest: "cafef00d",
        summary: "Controller for the synthetic widget model.",
        public_symbols: ["WidgetsController#index"],
        route_mappings: ["GET /widgets"]
      )

      json = capture_stdout { rake.invoke_task("ruby_sage:export_artifacts") }
      payload = JSON.parse(json)
      expect(payload["version"]).to eq(1)
      expect(payload["artifacts"].length).to eq(2)
      expect(payload["git_sha"]).to eq("abc123")

      with_stdin(json) do
        capture_stdout { rake.invoke_task("ruby_sage:import_artifacts") }
      end

      latest = RubySage::Scan.order(id: :desc).first
      expect(latest.id).not_to eq(scan.id)
      expect(latest.git_sha).to eq("abc123")
      expect(latest.artifacts.count).to eq(2)
      expect(latest.artifacts.pluck(:path)).to contain_exactly(
        "app/models/widget.rb",
        "app/controllers/widgets_controller.rb"
      )
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  def with_stdin(string)
    original = $stdin
    $stdin = StringIO.new(string)
    yield
  ensure
    $stdin = original
  end
end
