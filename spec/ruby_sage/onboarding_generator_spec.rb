# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::OnboardingGenerator do
  before do
    RubySage.reset_configuration!
    RubySage::Artifact.delete_all
    RubySage::Scan.delete_all
  end

  after do
    RubySage.reset_configuration!
    RubySage::Artifact.delete_all
    RubySage::Scan.delete_all
  end

  describe "#run" do
    it "raises when no completed scan exists" do
      expect { described_class.new.run }.to raise_error(RuntimeError, /No completed scan/)
    end

    it "writes ONBOARDING.md and AGENT_PRIMER.md and returns their paths" do
      seed_scan
      stub_provider_with("# Onboarding Guide\n\nThis is a test app.", "# Agent Primer\n\nTest primer.")

      Dir.mktmpdir do |tmpdir|
        result = described_class.new(host_root: tmpdir).run

        expect(result[:onboarding_path]).to end_with("ONBOARDING.md")
        expect(result[:primer_path]).to end_with("AGENT_PRIMER.md")
        expect(File.read(result[:onboarding_path])).to include("Onboarding Guide")
        expect(File.read(result[:primer_path])).to include("Agent Primer")
      end
    end

    it "calls the provider twice (once per document)" do
      seed_scan
      provider = stub_provider_with("onboarding content", "primer content")

      Dir.mktmpdir { |tmpdir| described_class.new(host_root: tmpdir).run }

      expect(provider).to have_received(:chat).exactly(2).times
    end
  end

  def seed_scan
    scan = RubySage::Scan.create!(status: "completed", finished_at: Time.current, file_count: 1)
    RubySage::Artifact.create!(
      scan: scan, path: "app/models/post.rb", kind: "model",
      digest: "abc", summary: "Post model."
    )
    scan
  end

  def stub_provider_with(*answers)
    responses = answers.map { |a| { answer: a, citations: [], usage: {} } }
    provider = instance_double(RubySage::Providers::Base)
    allow(provider).to receive(:chat).and_return(*responses)
    allow(RubySage).to receive(:provider).and_return(provider)
    provider
  end
end
