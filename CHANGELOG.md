# Changelog

## [0.3.1] - 2026-05-18

### Changed

- Internal cleanup: factored the syncer's `run` into smaller methods, split `citation_for` into kind-specific helpers, extracted the slug-format error message into a constant, and renamed an internal predicate to satisfy `Naming/PredicateMethod`. No behavior changes; rubocop now reports 0 offenses across the gem.

## [0.3.0] - 2026-05-18

### Added

- **Curated knowledge layer.** A new `RubySage::KnowledgeChunk` model (table: `ruby_sage_knowledge_chunks`) stores human-authored how-to / FAQ entries that the retriever surfaces alongside auto-summarized code artifacts. Three doors read the same rows: the chat widget (via the retriever), an admin CRUD at `/ruby_sage/admin/knowledge`, and a browsable index + show pages at `/ruby_sage/help`. Knowledge entries outrank artifacts in `:admin` and `:user` modes (multiplier `config.knowledge_boost`, default 3.0) because human-curated trumps inferred.
- **YAML-first authoring convention.** Drop YAML files under `config/ruby_sage/knowledge/*.yml` (configurable via `config.knowledge_path`). Each file is an array of entries with `slug`, `title`, `body` (markdown), and optional `tags`, `audiences`, `url`, `video_url`, `position`, `published`. `rake ruby_sage:knowledge:sync` upserts entries by slug into the database with `source: "yaml"`; rows whose slugs disappear from the YAML are removed on the next sync. Admin-authored rows (`source: "admin_ui"`) are never overwritten.
- **Agent-driven knowledge seeding.** `rake ruby_sage:knowledge:plan` walks the host's controllers and writes a candidate workflow list + `KNOWLEDGE_INSTRUCTIONS.md` for a local coding agent to expand into a `tmp/ruby_sage/knowledge.yml`. `rake ruby_sage:knowledge:apply` copies that file into `config/ruby_sage/knowledge/seeded.yml` and runs sync. Zero LLM tokens spent — same pattern as the existing agent-driven scan flow.
- **`/ruby_sage/help`** — public-ish readable index for end users / admins who don't know where to start. ILIKE-based search across title/body/slug/tags, tag-facet sidebar, markdown-rendered show pages, audience-filtered by the configured `mode`. Citations from the chat widget link here.
- **`/ruby_sage/admin/knowledge`** — admin CRUD. New / edit / delete / reorder. YAML-sourced entries are read-only (with an explanatory message) because the YAML file is the source of truth.
- `RubySage::MarkdownRenderer` — auto-detects `kramdown` when available, falls back to Rails' `simple_format`. Override entirely via `config.markdown_renderer` for hosts that want their own renderer.
- New configuration knobs: `knowledge_path`, `knowledge_boost`, `markdown_renderer`.
- Doctor: `check_knowledge_base_present` warns when `mode` is `:admin` or `:user` and zero published knowledge entries exist.
- Retriever return shape adds a `knowledge:` key alongside `artifacts:`. Citations gain a `kind: "knowledge"` variant with `slug`, `title`, `tags`, and `snippet`. Chat controller injects curated knowledge bodies into the cached LLM context before code summaries, with a system note telling the model to prefer curated content when applicable.

### Also added (previously unreleased — bundled into the 0.3.0 release)

- **`rake ruby_sage:doctor`** — diagnostic task that checks common install problems (provider/api_key, auth_check, scans present + recent, audience tagging coverage, `:user`-mode safety, `:admin` DB query safety, chat_turns table) and reports findings with actionable fixes. Exits non-zero on any error so it slots cleanly into a CI smoke test after a deploy. Format: `✓ check_name  message  ↳ fix`.
- **USD cost calculator.** New `RubySage::CostCalculator` ships pricing tables for current Anthropic + OpenAI models (Opus 4.7, Sonnet 4.6, Haiku 4.5, GPT-4.1, GPT-4.1 mini), accounts for cache-read and cache-write discounts separately. `ChatTurn#cost_usd` exposes the per-turn cost and the admin views show both per-turn and last-30-days aggregate spend in USD. `config.model_pricing` accepts host overrides — add a custom model or update prices without waiting for a gem release.
- `ChatTurn#model` column captures which provider model handled the turn (so cost calculation works on historical rows even after `config.model` changes).
- **Chat turn audit + usage persistence.** Every chat-widget exchange now writes a `RubySage::ChatTurn` row capturing question, answer, mode, tool calls (including the SQL the model ran in `:admin` mode), citations, token usage, and asker identity (when `config.identify_asker` is set). Powers the new admin audit dashboard at `/ruby_sage/admin/chat_turns` and is the data backbone for the future SaaS usage metering. Per-turn writes are wrapped in begin/rescue so persistence failures never break a chat response.
- New migration creating `ruby_sage_chat_turns`. `Scan has_many :chat_turns, dependent: :nullify` so deleting an old scan doesn't cascade-destroy historical turns.
- Admin views: `/ruby_sage/admin/chat_turns` (filterable list with last-30-days usage stats) and `/ruby_sage/admin/chat_turns/:id` (full detail with tool-call audit).
- `RubySage::ChatTurnRecorder` — extracted recording logic, independently testable.
- Configuration: `config.persist_chat_turns` (default true) and `config.identify_asker` (callable, optional).
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
