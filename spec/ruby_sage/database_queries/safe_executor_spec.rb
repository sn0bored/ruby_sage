# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::DatabaseQueries::SafeExecutor do
  let(:scan) { RubySage::Scan.create!(status: "completed", finished_at: Time.current) }

  before do
    RubySage::Artifact.delete_all
    RubySage::Scan.delete_all
  end

  after do
    RubySage::Artifact.delete_all
    RubySage::Scan.delete_all
  end

  describe "successful SELECT execution" do
    it "returns rows, columns, and counts for a valid SELECT" do
      RubySage::Artifact.create!(scan: scan, path: "app/models/user.rb", kind: "model", digest: "a")
      RubySage::Artifact.create!(scan: scan, path: "app/models/post.rb", kind: "model", digest: "b")

      result = described_class.new.call(sql: "SELECT path, kind FROM ruby_sage_artifacts ORDER BY path")

      expect(result[:columns]).to eq(%w[path kind])
      expect(result[:rows]).to eq([
                                    ["app/models/post.rb", "model"],
                                    ["app/models/user.rb", "model"]
                                  ])
      expect(result[:row_count]).to eq(2)
      expect(result[:truncated]).to be(false)
      expect(result[:executed_sql]).to include("LIMIT")
    end

    it "appends a LIMIT when none is provided" do
      result = described_class.new(max_rows: 5).call(sql: "SELECT * FROM ruby_sage_scans")

      expect(result[:executed_sql]).to end_with("LIMIT 5")
    end

    it "leaves an explicit LIMIT alone" do
      result = described_class.new.call(sql: "SELECT * FROM ruby_sage_scans LIMIT 3")

      expect(result[:executed_sql]).to eq("SELECT * FROM ruby_sage_scans LIMIT 3")
    end

    it "marks results as truncated when more rows would have come back" do
      5.times { |i| RubySage::Artifact.create!(scan: scan, path: "p#{i}", kind: "k", digest: "d#{i}") }

      result = described_class.new(max_rows: 2).call(sql: "SELECT path FROM ruby_sage_artifacts ORDER BY path LIMIT 5")

      expect(result[:rows].size).to eq(2)
      expect(result[:truncated]).to be(true)
    end

    it "truncates oversized string cells" do
      huge = "x" * 2_000
      RubySage::Artifact.create!(scan: scan, path: "p", kind: "k", digest: "d", summary: huge)

      result = described_class.new(max_cell_bytes: 50).call(sql: "SELECT summary FROM ruby_sage_artifacts")

      expect(result[:rows].first.first.bytesize).to be <= 60
      expect(result[:rows].first.first).to end_with("…")
    end
  end

  describe "rolls back any side effects" do
    it "discards INSERT side effects even though INSERT would be rejected at validation time" do
      # Belt-and-suspenders: even if validation were bypassed, the transaction rollback prevents persistence.
      executor = described_class.new
      sneaky_sql = "INSERT INTO ruby_sage_scans (status) VALUES ('completed')"

      expect { executor.call(sql: sneaky_sql) }.to raise_error(described_class::UnsafeQuery)
      expect(RubySage::Scan.count).to eq(0)
    end
  end

  describe "validation rejects unsafe queries" do
    [
      ["empty SQL", "   "],
      ["UPDATE", "UPDATE ruby_sage_scans SET status = 'failed'"],
      ["DELETE", "DELETE FROM ruby_sage_scans"],
      ["DROP TABLE", "DROP TABLE ruby_sage_scans"],
      ["INSERT", "INSERT INTO ruby_sage_scans (status) VALUES ('x')"],
      ["TRUNCATE", "TRUNCATE TABLE ruby_sage_scans"],
      ["multi-statement SELECT then DELETE", "SELECT 1; DELETE FROM ruby_sage_scans"],
      ["multi-statement with leading whitespace", "  SELECT 1; UPDATE ruby_sage_scans SET status='x'"],
      ["leading comment hiding UPDATE", "-- comment\nUPDATE ruby_sage_scans SET status='x'"]
    ].each do |label, sql|
      it "rejects #{label}" do
        expect { described_class.new.call(sql: sql) }.to raise_error(described_class::UnsafeQuery)
      end
    end

    it "rejects SQL longer than the configured limit" do
      huge = "SELECT * FROM ruby_sage_scans WHERE id IN (#{Array.new(2000) { '1' }.join(',')})"
      expect do
        described_class.new(max_sql_length: 200).call(sql: huge)
      end.to raise_error(described_class::UnsafeQuery, /exceeds/)
    end

    it "tolerates a trailing semicolon" do
      result = described_class.new.call(sql: "SELECT 1 AS one;")
      expect(result[:rows].first).to eq([1])
    end

    it "tolerates a semicolon inside a string literal" do
      result = described_class.new.call(sql: "SELECT 'a;b' AS pair")
      expect(result[:rows].first).to eq(["a;b"])
    end
  end

  describe "DB errors return a structured error instead of raising" do
    it "returns an error hash when the table does not exist" do
      result = described_class.new.call(sql: "SELECT * FROM nonexistent_table")

      expect(result[:error]).to eq("query_failed")
      expect(result[:message]).to be_a(String)
      expect(result[:executed_sql]).to include("nonexistent_table")
    end
  end
end
