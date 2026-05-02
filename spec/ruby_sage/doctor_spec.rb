# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::Doctor do
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

  def find(check_name)
    described_class.new.run.find { |f| f.check == check_name.to_s }
  end

  describe "auth_check" do
    it "errors when no auth_check is configured" do
      finding = find("auth_check")
      expect(finding.status).to eq(:error)
      expect(finding.fix).to include("auth_check")
    end

    it "ok when an auth_check is configured" do
      RubySage.configure { |c| c.auth_check = ->(_) { true } }
      expect(find("auth_check").status).to eq(:ok)
    end
  end

  describe "scans" do
    it "errors when no completed scan exists" do
      finding = find("scans")
      expect(finding.status).to eq(:error)
      expect(finding.fix).to include("ruby_sage:scan")
    end

    it "ok when at least one completed scan exists" do
      RubySage::Scan.create!(status: "completed", finished_at: Time.current)
      expect(find("scans").status).to eq(:ok)
    end
  end

  describe "scan_freshness" do
    it "warns when the latest scan is older than 7 days" do
      RubySage::Scan.create!(status: "completed", finished_at: 10.days.ago)
      expect(find("scan_freshness").status).to eq(:warn)
    end

    it "ok when the latest scan is recent" do
      RubySage::Scan.create!(status: "completed", finished_at: 2.days.ago)
      expect(find("scan_freshness").status).to eq(:ok)
    end
  end

  describe "user_mode" do
    it "warns when mode is :user but no artifacts are user-visible" do
      RubySage.configure do |c|
        c.mode = :user
        c.auth_check = ->(_) { true }
      end
      scan = RubySage::Scan.create!(status: "completed", finished_at: Time.current)
      RubySage::Artifact.create!(scan: scan, path: "x", digest: "x", audiences: %w[developer])

      finding = find("user_mode")
      expect(finding.status).to eq(:warn)
      expect(finding.fix).to include("user_facing_paths")
    end
  end

  describe "db_queries" do
    it "warns when enabled but mode is not admin" do
      RubySage.configure do |c|
        c.enable_database_queries = true
        c.mode = :developer
      end
      expect(find("db_queries").status).to eq(:warn)
    end

    it "warns when enabled in admin mode but no read-only connection set" do
      RubySage.configure do |c|
        c.enable_database_queries = true
        c.mode = :admin
      end
      finding = find("db_queries")
      expect(finding.status).to eq(:warn)
      expect(finding.fix).to include("query_connection")
    end
  end

  describe "the rake-task-style report" do
    it "labels findings with ✓ / ! / ✗" do
      findings = described_class.new.run
      severities = findings.map(&:severity_label).uniq
      expect(severities - %w[✓ ! ✗]).to be_empty
    end
  end
end
