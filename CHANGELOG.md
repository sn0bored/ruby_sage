# Changelog

## [Unreleased]

### Added

- `examples/` directory with end-to-end walkthroughs: agent-driven scan, admin database queries, prod sync. Includes a sample `summaries.json` showing the agent contract.
- `SAAS_PLAN.md` — design sketch for the v2 hosted product (RubySage Cloud).
- README "Compared to alternatives" section positioning RubySage against Cursor codebase chat, Continue/Aider, ChatGPT/Claude.ai file uploads, and Sourcegraph Cody.
- Agentic database queries for `:admin` mode. When `config.enable_database_queries = true` and the configured `mode` is `:admin`, the chat loop exposes two tools to the model: `query_database` (read-only SELECT) and `describe_table` (column introspection). The model decides when to query live data vs. answer from artifact context. Three defense layers on every query: SELECT-only validation, mandatory transaction rollback (so any write that slipped past validation cannot persist), and PostgreSQL `statement_timeout`. Hard caps on rows (`max_query_rows`, default 100), cell size (1KB), SQL length (4KB), and tool-loop iterations (`tool_loop_max_iterations`, default 5). Strongest defense remains a read-only DB user via `config.query_connection`.
- `RubySage::DatabaseQueries::SafeExecutor` — standalone read-only SQL executor (usable outside the tool loop).
- `RubySage::Tools::Base`, `Tools::DatabaseQuery`, `Tools::DescribeTable`, `Tools::Registry`.
- `RubySage::ToolLoop` — drives provider/tool-call rounds for one chat turn.
- `Providers::Anthropic#chat` accepts `tools:` and returns `:tool_calls`, `:stop_reason`, `:raw_content` for tool-loop support. `Providers::OpenAI#chat` rejects tools with a clear error (V1 OpenAI does not support tool calling).
- `config.query_scope` callable. Returns a SQL fragment ("organization_id = 42") that gets appended to the admin system prompt as a multi-tenant scoping reminder. V1 is prompt-level; for hard tenant isolation, pair with `query_connection` and database-level row security.
- Chat response now includes `tool_calls` and `iterations` for transparency when a tool loop ran.
- Per-mode artifact scoping. Each scanned artifact is tagged with an `audiences` array (`developer`, `admin`, `user`) at scan time via `RubySage::AudienceClassifier`. Retriever filters by the configured `mode` so a `:user` chat never sees `:developer`-only files. Default heuristic is conservative: services/jobs/policies/queries/lib/config are developer-only; models/controllers/views/mailers/schema/admin namespace add `:admin`; the `:user` audience is empty until the host opts in via `config.user_facing_paths` (glob list) or `config.audience_for` (callable).
- Hardened `:user` system prompt: explicit rules forbidding file paths, class names, code snippets, SQL, and architectural details, plus a fixed refusal sentence for "how is this built" questions.
- Agent-driven scan flow: `rake ruby_sage:scan:plan` writes a manifest + `INSTRUCTIONS.md` that any local coding agent (Claude Code, Codex, Cursor) can fill in, then `rake ruby_sage:scan:apply` ingests the agent's `summaries.json` and persists a completed `Scan`. Removes the API-token cost of summarization for developers who already pay for an agent. The same flow ships manifest + summaries to production for zero-LLM-spend prod installs.
- `RubySage::AgentScan` module: `Planner`, `Applier`, `Instructions`. The agent's `summaries.json` may include an optional `audience_overrides` hash to override per-file audience tags — useful for marking specific files user-facing without writing a `config.audience_for` callable.
- `Artifact#visible_in_mode?`. Artifacts created before audience tagging (no `audiences` set) are visible in every mode, preserving backwards compatibility.
- `Scanner::ArtifactBuilder#attributes_for` — exposes per-file artifact attributes without persisting, enabling the manifest builder to share the scanner's classification, redaction, and digest logic.

## [0.1.0] - 2026-05-01

First public release. Supports Rails 5.2+ / Ruby 2.7+.

- Rails install generator (`rails g ruby_sage:install`).
- Sync rake tasks: `ruby_sage:export_artifacts` and `ruby_sage:import_artifacts` for shipping pre-baked snapshots between environments.
- Comprehensive README: install, providers, scan strategies, cost estimates, AI agent integration, security posture, roadmap.
- Widget helper + partial, vanilla JS drawer with page-context capture, scoped CSS, Turbo-safe mount lifecycle, CSP nonce support, csp_nonce config hook.
- Anthropic + OpenAI providers (Net::HTTP, no new runtime deps), Anthropic prompt caching via cache_control, chat controller with retrieval-and-citations response shape, error handling for provider failures and missing params.
- Retriever (keyword + symbol scoring with page-context boost), internal /retrieve endpoint, RubySage.context_for convenience entry point.
- Artifact schema (ruby_sage_scans + ruby_sage_artifacts), Scanner walker with classification + symbol extraction, Summarizer (graceful fallback when no API key), SecretRedactor, file-based locking, retention cleanup, rake ruby_sage:scan task.
- Configuration object, server-side authorization, asset pipeline + CSP nonce hook, provider abstraction interface, health endpoint.
- Gem skeleton, dummy host app, RSpec setup, RuboCop, CI matrix across Rails 5.2-8.0 × Ruby 2.7-3.3.
