# frozen_string_literal: true

require "ruby_sage/agent_scan/instructions"
require "ruby_sage/agent_scan/planner"
require "ruby_sage/agent_scan/applier"

module RubySage
  # Agent-driven scanning. Lets a local coding agent (Claude Code, Codex, Cursor)
  # produce file summaries instead of the gem calling a paid LLM API. The host
  # writes a manifest with +Planner+, hands it to the agent, then ingests the
  # agent's summaries with +Applier+.
  module AgentScan
    DEFAULT_OUTPUT_DIRNAME = "tmp/ruby_sage"
    MANIFEST_FILENAME = "manifest.json"
    SUMMARIES_FILENAME = "summaries.json"
    INSTRUCTIONS_FILENAME = "INSTRUCTIONS.md"
    SCHEMA_VERSION = 1
  end
end
