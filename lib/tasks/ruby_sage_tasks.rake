# frozen_string_literal: true

require "json"

namespace :ruby_sage do
  desc "Scan the host application's codebase and produce a knowledge snapshot."
  task scan: :environment do
    scan = RubySage::Scanner.new(host_root: Rails.root).run
    puts "Scan ##{scan.id} #{scan.status} - #{scan.file_count} files, " \
         "#{scan.artifacts.count} artifacts."
  end

  namespace :scan do
    desc "Plan an agent-driven scan: write manifest.json + INSTRUCTIONS.md for a coding agent to summarize."
    task plan: :environment do
      output_dir = ENV.fetch("OUTPUT_DIR", nil)
      result = RubySage::AgentScan::Planner.new(
        host_root: Rails.root,
        output_dir: output_dir
      ).run

      puts "Wrote manifest:     #{result[:manifest_path]}"
      puts "Wrote instructions: #{result[:instructions_path]}"
      puts "Files in manifest:  #{result[:file_count]} (#{result[:needs_summary_count]} need new summaries)"
      puts ""
      puts "Next: have your coding agent read the instructions file and write"
      puts "  #{result[:summaries_path]}"
      puts "Then run: bundle exec rake ruby_sage:scan:apply"
    end

    desc "Apply an agent-produced summaries.json to a manifest, creating a new completed Scan."
    task apply: :environment do
      output_dir = ENV.fetch("OUTPUT_DIR", Rails.root.join(RubySage::AgentScan::DEFAULT_OUTPUT_DIRNAME).to_s)
      manifest_path = ENV.fetch("MANIFEST", File.join(output_dir, RubySage::AgentScan::MANIFEST_FILENAME))
      summaries_path = ENV.fetch("SUMMARIES", File.join(output_dir, RubySage::AgentScan::SUMMARIES_FILENAME))

      scan = RubySage::AgentScan::Applier.new(
        manifest_path: manifest_path,
        summaries_path: summaries_path
      ).run

      summarized = scan.artifacts.where.not(summary: nil).count
      puts "Scan ##{scan.id} completed - #{scan.file_count} files, #{summarized} with summaries."
    end
  end

  desc "Export the latest completed scan as JSON to STDOUT."
  task export_artifacts: :environment do
    scan = RubySage::Scan.latest_completed.first
    abort "No completed scan found. Run `rake ruby_sage:scan` first." if scan.nil?

    payload = {
      "version" => 1,
      "exported_at" => Time.now.utc.iso8601,
      "ruby_version" => scan.ruby_version,
      "rails_version" => scan.rails_version,
      "git_sha" => scan.git_sha,
      "file_count" => scan.file_count,
      "artifacts" => scan.artifacts.map do |artifact|
        {
          "path" => artifact.path,
          "kind" => artifact.kind,
          "digest" => artifact.digest,
          "summary" => artifact.summary,
          "public_symbols" => artifact.public_symbols,
          "route_mappings" => artifact.route_mappings
        }
      end
    }
    puts JSON.pretty_generate(payload)
  end

  desc "Generate ONBOARDING.md and AGENT_PRIMER.md from the latest scan."
  task onboard: :environment do
    result = RubySage::OnboardingGenerator.new.run
    puts "Wrote #{result[:onboarding_path]}"
    puts "Wrote #{result[:primer_path]}"
  end

  desc "Ask a question against the knowledge base and print the answer. Usage: rake 'ruby_sage:ask[your question here]'"
  task :ask, [:query] => :environment do |_task, args|
    query = args[:query] || ENV.fetch("QUERY", nil)
    abort "Usage: rake 'ruby_sage:ask[your question]'  or  QUERY='...' rake ruby_sage:ask" if query.to_s.strip.empty?

    RubySage::CliChat.new.run(query)
  end

  desc "Diagnose common RubySage install problems and report fixes."
  task doctor: :environment do
    findings = RubySage::Doctor.new.run
    width = findings.map { |f| f.check.length }.max
    findings.each do |finding|
      puts format("%s  %-#{width}s  %s", finding.severity_label, finding.check, finding.message)
      puts format("   %-#{width}s  ↳ %s", "", finding.fix) if finding.fix
    end
    errors = findings.count { |f| f.status == :error }
    warns = findings.count { |f| f.status == :warn }
    puts ""
    puts "#{findings.size} checks: #{findings.count(&:ok?)} ok, #{warns} warn, #{errors} error"
    exit(errors.positive? ? 1 : 0)
  end

  desc "Import a previously-exported scan from STDIN as a new completed Scan."
  task import_artifacts: :environment do
    payload = JSON.parse($stdin.read)
    abort "Unsupported export version: #{payload['version']}" unless payload["version"] == 1

    scan = RubySage::Scan.create!(
      status: "completed",
      git_sha: payload["git_sha"],
      ruby_version: payload["ruby_version"],
      rails_version: payload["rails_version"],
      file_count: payload["file_count"],
      started_at: Time.current,
      finished_at: Time.current
    )
    Array(payload["artifacts"]).each do |entry|
      RubySage::Artifact.create!(
        scan: scan,
        path: entry["path"],
        kind: entry["kind"],
        digest: entry["digest"],
        summary: entry["summary"],
        public_symbols: entry["public_symbols"],
        route_mappings: entry["route_mappings"]
      )
    end
    puts "Imported scan ##{scan.id} with #{scan.artifacts.count} artifacts."
  end
end
