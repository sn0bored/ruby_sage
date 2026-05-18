# frozen_string_literal: true

require "fileutils"
require "pathname"

module RubySage
  module Knowledge
    # Walks the host app surfacing candidate admin/user workflows that deserve
    # knowledge entries, then writes a candidate list + instructions a local
    # coding agent can flesh into a knowledge.yml file. Zero LLM tokens spent —
    # the agent does the reading and writing.
    class AgentPlanner
      CANDIDATES_FILENAME = "knowledge_candidates.md"
      INSTRUCTIONS_FILENAME = "KNOWLEDGE_INSTRUCTIONS.md"
      OUTPUT_FILENAME = "knowledge.yml"

      # @param host_root [String, Pathname]
      # @param output_dir [String, Pathname]
      def initialize(host_root:, output_dir:)
        @host_root = Pathname(host_root).expand_path
        @output_dir = Pathname(output_dir).expand_path
      end

      # @return [Hash]
      def run
        FileUtils.mkdir_p(@output_dir)

        candidates = collect_candidates
        candidates_path = @output_dir.join(CANDIDATES_FILENAME)
        instructions_path = @output_dir.join(INSTRUCTIONS_FILENAME)
        knowledge_yml_path = @output_dir.join(OUTPUT_FILENAME)

        File.write(candidates_path, render_candidates(candidates))
        File.write(instructions_path, render_instructions(candidates_path, knowledge_yml_path))

        {
          candidates_path: candidates_path.to_s,
          instructions_path: instructions_path.to_s,
          knowledge_yml_path: knowledge_yml_path.to_s,
          candidate_count: candidates.size
        }
      end

      private

      # Surfaces routes + non-trivial controller actions that are likely
      # candidates for a how-to entry. Heuristic: any non-RESTful collection/
      # member action that isn't a CRUD verb, plus actions on namespaced
      # admin/reports/imports controllers.
      def collect_candidates
        controller_files = Dir.glob(@host_root.join("app", "controllers", "**", "*.rb"))
        controller_files.flat_map { |file| candidates_from(file) }.sort_by { |c| c[:path] }
      end

      def candidates_from(file)
        rel = Pathname.new(file).relative_path_from(@host_root).to_s
        contents = File.read(file)
        controller = rel.sub(%r{\Aapp/controllers/}, "").sub(/_controller\.rb\z/, "")

        actions = contents.scan(/^\s*def\s+([a-z_][a-z0-9_]*)/).flatten
        custom = actions - %w[index show new edit create update destroy]
        relevant = relevant_controller?(controller) ? actions : custom

        relevant.map do |action|
          { path: rel, controller: controller, action: action }
        end
      end

      def relevant_controller?(controller)
        controller.start_with?("admin/") || controller.include?("report") ||
          controller.include?("import") || controller.include?("export")
      end

      def render_candidates(candidates)
        lines = ["# Knowledge entry candidates", "",
                 "Auto-generated list of controllers/actions that likely deserve a how-to entry.",
                 "Read each one, decide which deserve documentation, and write the YAML.",
                 ""]
        grouped = candidates.group_by { |c| c[:controller] }
        grouped.each do |controller, group|
          lines << "## #{controller}"
          group.each { |c| lines << "- `#{c[:action]}` — see `#{c[:path]}`" }
          lines << ""
        end
        lines.join("\n")
      end

      def render_instructions(candidates_path, output_path)
        <<~MD
          # Knowledge seeding — instructions for the local coding agent

          Goal: produce starter knowledge entries the host app's admins can read
          (at `/ruby_sage/help`) and the chat widget can retrieve from.

          ## Inputs

          - `#{candidates_path}` — heuristic list of controller actions that might
            deserve an entry. Treat as a starting point, not a final list.
          - The host app source tree at `#{@host_root}`. Look at views, controllers,
            services, README, CLAUDE.md.

          ## Output

          Write `#{output_path}` as a YAML array of entries. Schema per entry:

          ```yaml
          - slug: create-monthly-report          # required, kebab-case
            title: How to create the monthly membership report  # required
            audiences: [admin]                   # subset of [developer, admin, user]
            tags: [reports, monthly]             # optional
            body: |                              # required, markdown
              ## Open the report

              Go to **Reports → Monthly Membership** in the navbar.

              ## Choose a month

              ...
            url: https://...                     # optional external link
            video_url: https://...               # optional tutorial video
            position: 10                         # optional, lower = higher in list
            published: true                      # optional, defaults to true
          ```

          ## Rules

          - Write for the **end user of the host app**, not for a developer.
            No file paths, no class names, no SQL. Describe what the admin sees
            in the UI and what to click.
          - Markdown bodies should be short — 2-6 paragraphs. Use H2 headers,
            bullet lists, and bold for emphasis.
          - When two entries cover related workflows, give them shared tags so
            users can find each other.
          - Skip auth, registration, and password-reset workflows — those are
            Devise defaults and don't need entries unless the host app customized them.

          ## After you write the file

          Run: `bundle exec rake ruby_sage:knowledge:apply`

          That copies your file into `config/ruby_sage/knowledge/seeded.yml` and
          runs `knowledge:sync` to upsert the entries into the database.
        MD
      end
    end
  end
end
