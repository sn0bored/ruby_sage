# frozen_string_literal: true

require "json"

namespace :ruby_sage do
  desc "Scan the host application's codebase and produce a knowledge snapshot."
  task scan: :environment do
    scan = RubySage::Scanner.new(host_root: Rails.root).run
    puts "Scan ##{scan.id} #{scan.status} - #{scan.file_count} files, " \
         "#{scan.artifacts.count} artifacts."
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
