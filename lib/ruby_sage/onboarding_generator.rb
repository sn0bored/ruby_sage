# frozen_string_literal: true

module RubySage
  # Synthesises a human-readable ONBOARDING.md and a compact agent primer from
  # the latest completed scan. Writes both to disk.
  #
  # @example
  #   result = RubySage::OnboardingGenerator.new.run
  #   puts result[:onboarding_path]  # => "docs/ONBOARDING.md"
  #   puts result[:primer_path]      # => "docs/AGENT_PRIMER.md"
  class OnboardingGenerator
    ONBOARDING_PROMPT = <<~PROMPT
      You are generating developer onboarding documentation for a Ruby on Rails application.
      You will receive a structured summary of every scanned file. Produce a Markdown document with these sections:

      # Onboarding Guide

      ## What is this app?
      One paragraph describing the product and who uses it.

      ## Tech Stack
      Bullet list: framework, database, key gems, background jobs, asset pipeline, testing.

      ## Data Model
      The 8-10 most important models, one line each: name, what it represents, key associations.

      ## Key Workflows
      3-5 numbered workflows (e.g. "User signup", "Billing flow"). For each: 2-3 sentences describing the happy path and the key files/classes involved.

      ## Where to Start
      Ordered list of 5 files a new developer should read first, with one-line explanation for each.

      ## Gotchas
      3-5 bullet points of non-obvious things: naming conventions, architectural quirks, things that trip up new contributors.

      Be specific. Reference actual class names, file paths, and gem names from the context. No filler.
    PROMPT

    AGENT_PRIMER_PROMPT = <<~PROMPT
      You are generating a compact context primer for an AI coding agent working on a Ruby on Rails application.
      You will receive a structured summary of every scanned file. Produce a Markdown document with these sections:

      # Agent Primer — [App Name]

      ## App in one sentence
      ## Stack (one line each): Ruby version, Rails version, DB, background jobs, auth, key gems
      ## Domain model (comma-separated model names with one-word description)
      ## Service layer (list key service class names and what they do, one line each)
      ## Patterns to follow (3-5 bullet points: naming, architecture, testing conventions)
      ## What NOT to do (3 bullet points of anti-patterns specific to this codebase)

      Keep it under 600 words. This gets prepended to every coding prompt.
    PROMPT

    MAX_CONTEXT_ARTIFACTS = 80

    # @param host_root [Pathname, String] root of the host Rails app.
    # @param config [RubySage::Configuration]
    def initialize(host_root: Rails.root, config: RubySage.configuration)
      @host_root = Pathname(host_root)
      @config = config
    end

    # Generates ONBOARDING.md and AGENT_PRIMER.md from the latest scan.
    #
    # @return [Hash] with :onboarding_path, :primer_path, :scan_id keys.
    # @raise [RuntimeError] if no completed scan exists.
    def run
      scan = Scan.latest_completed.first
      raise "No completed scan found. Run `rake ruby_sage:scan` first." if scan.nil?

      context = build_context(scan)

      onboarding = generate(context, ONBOARDING_PROMPT)
      primer = generate(context, AGENT_PRIMER_PROMPT)

      docs_dir = @host_root.join("docs")
      FileUtils.mkdir_p(docs_dir)

      onboarding_path = docs_dir.join("ONBOARDING.md")
      primer_path = docs_dir.join("AGENT_PRIMER.md")

      onboarding_path.write(onboarding)
      primer_path.write(primer)

      { onboarding_path: onboarding_path.to_s, primer_path: primer_path.to_s, scan_id: scan.id }
    end

    private

    # Builds a condensed artifact context string, prioritising high-signal kinds.
    #
    # @param scan [RubySage::Scan]
    # @return [String]
    def build_context(scan)
      artifacts = scan.artifacts.to_a
      prioritized = prioritize(artifacts).first(MAX_CONTEXT_ARTIFACTS)

      blocks = prioritized.map do |artifact|
        symbols = Array(artifact.public_symbols).join(", ")
        "### #{artifact.path} (#{artifact.kind})\n" \
          "Symbols: #{symbols.empty? ? '—' : symbols}\n" \
          "#{artifact.summary || '(no summary)'}"
      end

      "Codebase artifact summaries (#{prioritized.size} of #{artifacts.size} files):\n\n" \
        "#{blocks.join("\n\n---\n\n")}"
    end

    # Orders artifacts so models, controllers, and services appear first.
    #
    # @param artifacts [Array<RubySage::Artifact>]
    # @return [Array<RubySage::Artifact>]
    def prioritize(artifacts)
      priority = { "model" => 0, "controller" => 1, "service" => 2,
                   "job" => 3, "policy" => 4, "mailer" => 5 }
      artifacts.sort_by { |a| [priority.fetch(a.kind.to_s, 99), a.path] }
    end

    # Calls the provider to generate a synthesis document.
    #
    # @param context [String]
    # @param system_prompt [String]
    # @return [String]
    def generate(context, system_prompt)
      response = RubySage.provider.chat(
        system_prompt: system_prompt,
        cached_context: context,
        messages: [{ role: "user", content: "Generate the document now." }]
      )
      response[:answer]
    end
  end
end
