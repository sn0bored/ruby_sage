# RubySage — Architecture & Build Plan

## Compatibility

- **Ruby**: 2.7+. We deliberately support legacy Ruby so host apps don't have to upgrade before adopting RubySage. Code stays portable to 2.7.
- **Rails**: 5.2+. Engine, ActiveRecord, ActionController primitives we use have been stable since 5.2.
- **Asset pipeline**: Sprockets-only for V1. Propshaft compatibility deferred to v1.5.

Portability constraints for gem code:
- No `Data.define`, no shorthand hash-key punning (`{ x:, y: }`), no rightward assignment (`expr => var`), no anonymous block forwarding (`&`).
- Be explicit about kwargs at the Ruby 2.7 → 3.0 boundary. Use `**kwargs` consistently.
- No Rails-7-only idioms (e.g., `enum :status, [...]` symbol-first form). Use `enum status: { ... }` instead.
- No Zeitwerk-only autoload assumptions. Code should also work under classic loader (Rails 5.2 / 6.0 default).

CI verifies cross-version compatibility via a matrix in `.github/workflows/ci.yml`.

## Streaming-ready architecture (V1, not yet streaming)

Streaming responses (SSE) are deferred to v1.5, but the V1 architecture is shaped so we don't pay a rewrite tax later:

- **Provider interface**: `chat` accepts an optional block. V1 ignores the block and returns the full response. V1.5 implementations can yield chunks to the block while still buffering for the return value.
- **Chat controller**: V1 returns a single JSON response. The endpoint contract uses a response shape (`{ answer, citations, usage }`) compatible with progressive rendering — V1.5 swaps to an SSE response without changing the URL.
- **Widget JS**: V1 consumes the JSON response in one shot. V1.5 swaps to consuming an event stream — incremental token append is a small client-side change, not a UI rewrite.

## Quality bar

This gem aspires to Rails-core acceptability. Concretely:

- **Idiomatic Ruby.** SOLID. Small composable classes. Names reveal intent. No magic, no unexplained metaprogramming.
- **Public API documented.** Every public method has a YARD doc block (params, return, raises, example).
- **Backward compatibility from 0.1.0.** Semantic versioning. Deprecation warnings before removal. No silent breaking changes.
- **Minimal runtime dependencies.** Rails + Ruby stdlib only for V1. Provider HTTP calls use `Net::HTTP` or Rails' built-in HTTP client. Adding a dependency requires a justification.
- **Comprehensive RSpec coverage.** Edge cases tested. Mocking only at integration boundaries (HTTP, FS). No mocking of internal collaborators.
- **Code that reads like prose.** If a method needs a comment to explain WHAT, rename or refactor it. Comments explain WHY.
- **README worthy of a popular gem.** Install / configure / quickstart / API reference / contribute / license. With a screenshot of the widget.

RSpec green and RuboCop clean are **gates**, not aspirations. CI must be green before any phase is declared done.

## What it is

A Rails engine, distributed as the `ruby_sage` gem, that:

1. Scans the host app's codebase on a schedule.
2. Builds per-file artifacts (path, kind, summary, public symbols, route/action mapping).
3. Serves a `/ruby_sage/chat` endpoint that retrieves relevant artifacts for a question and returns an answer with citations.
4. Renders a floating chat widget via a single helper, droppable into any layout.

## Core architectural decisions

- **Retrieval, not snapshot-stuffing.** Per-file artifacts retrieved at query time. NOT a single giant snapshot doc shoved into every prompt.
- **Citations are mandatory.** Every chat response includes a list of files/symbols/routes used to construct the answer. No citation = no trust.
- **Anthropic prompt caching from day 1.** Stable retrieved artifacts (schema, README, frequently-cited files) get `cache_control` markers. Cuts repeat-call cost ~10x.
- **Page context resolves server-side.** Widget passes URL → server resolves to route → controller#action → injects the relevant artifacts into the user message.
- **Server-side auth enforcement.** `before_action` in the controller, not just a widget render check.
- **Public, no-data-leak.** This is an OSS gem under `sn0bored/ruby_sage`. The dummy host app for tests is 100% synthetic. Zero proprietary code, schemas, or env values may land in this repo.
- **Gem only.** Host-app integration lives in the host repo on its own branch, never here.

## Components

### Knowledge layer

- `RubySage::Scanner` — walks the host app and produces per-file artifacts.
- `RubySage::Artifact` model + migration — `path, kind, digest, summary, public_symbols (json), route_mappings (json), scanned_at, scan_id`.
- `RubySage::Scan` model — metadata: `git_sha, ruby_version, rails_version, started_at, finished_at, file_count, errors, status`.
- Rake task: `rake ruby_sage:scan` (manual or daily cron).
- Atomic writes, locking, retention: keep N most recent scans, delete older.
- Storage: compressed text columns in DB. FS/object-store option deferred to v1.5.

### Scanner scope

Default include:
- `app/models`, `app/controllers`, `app/services`, `app/jobs`, `app/mailers`, `app/policies`, `app/queries`, `app/serializers`, `app/decorators`, `app/helpers`, `app/components`, `app/workers`
- `config/routes.rb`
- `db/schema.rb`
- `README.md`, `CLAUDE.md`, `.cursorrules`
- View template paths (not full rendering, just file listing)

Default exclude:
- `vendor/`, `node_modules/`, `tmp/`, `log/`, `db/seeds.rb`, `db/data/`
- `config/credentials*`, `*.env*`, `*.key`, `*.pem`
- Anything matching the host app's `.gitignore`

Secret handling:
- KEEP `ENV[...]` symbol references — the model needs to know `STRIPE_SECRET_KEY` exists as a config dependency.
- REDACT actual values from any config file (e.g., `database.yml`, `cable.yml`).
- SKIP `credentials.yml.enc` entirely.

### Per-file summarization

At scan time, run a cheap LLM pass per file to produce:
- A 1-2 paragraph summary
- A list of public symbols (class/module names, public methods, route paths)

Cache by file digest — only re-summarize files whose digest changed since last scan.

### Retrieval layer

- `POST /ruby_sage/internal/retrieve` (testable without UI) — given `query` + optional `page_context (url)`, returns top-N artifacts with relevance scores and citations.
- V1 retrieval: keyword + symbol matching over artifact summaries and public symbols. Boost artifacts that match the resolved route from `page_context`.
- V2: pgvector embeddings. API contract designed to anticipate this — retrieval is a swappable component.

### Chat layer

- `POST /ruby_sage/chat` — takes `message` + optional `page_context (url, title)`.
- Resolves `page_context.url` server-side: route → controller#action → relevant artifacts.
- Calls retrieval to get top-N artifacts for `message`.
- Builds prompt: system + cached retrieved-artifact block + user message.
- Calls provider.
- Returns `{ answer, citations: [{ path, kind, line_range }] }`.
- Streaming/SSE deferred to v1.5 but interface designed for it (return shape allows incremental).

### Provider abstraction

- `RubySage::Providers::Anthropic` and `RubySage::Providers::OpenAI`.
- Anthropic uses prompt caching (`cache_control` on artifact block).
- Configurable: `provider`, `model`, `api_key`, `timeout`, `max_retries`.

### Widget

- `<%= ruby_sage_widget %>` helper.
- Floating button → drawer with chat input.
- Scope toggle: "This page" / "Whole app".
- **Non-inline assets**: JS and CSS served via Sprockets/Propshaft.
- **CSP nonce support**: configurable nonce source; falls back to attributes-based mounting.
- **Scoped CSS**: all classes prefixed `ruby-sage-`. Configurable z-index (default very high).
- **Turbo-safe**: mount lifecycle handles `turbo:load` / `turbo:before-cache`.
- Vanilla JS, zero deps.

### Configuration

```ruby
RubySage.configure do |config|
  config.provider = :anthropic
  config.api_key  = ENV["ANTHROPIC_API_KEY"]
  config.model    = "claude-sonnet-4-6"
  config.summarization_model = "claude-haiku-4-5"
  config.auth_check = -> { current_user&.admin? }
  config.scope = :admin    # :admin / :signed_in / :public_rate_limited
  config.scan_retention = 7  # keep N most recent scans
  config.scanner_include = [...]
  config.scanner_exclude = [...]
  config.csp_nonce = -> { request.content_security_policy_nonce }
end
```

## Build phases

Each phase ends with a passing test suite and a green CI run.

### Phase 0 — repo + dummy host app + RSpec (~1hr)

- Bootstrap Bundler gem skeleton (`bundle gem ruby_sage`).
- Set up `spec/dummy/` synthetic Rails app (no real-world code).
- RSpec + GitHub Actions CI.
- MIT LICENSE, RuboCop, basic gemspec metadata.

### Phase 1 — engine skeleton + config + auth + asset strategy + provider shell (~1-2hr)

- Rails engine: `RubySage::Engine`.
- Routes namespaced under `/ruby_sage`.
- `ApplicationController` base with `before_action :authorize_ruby_sage!`.
- Asset pipeline integration: declare manifest, ship CSS/JS from `app/assets/`.
- CSP nonce hook (configurable, with fallback).
- Provider abstraction interface: `RubySage::Providers::Base`.
- Configuration object with all keys above.
- Tests: engine mounts, routes resolve, auth blocks unauthorized, config defaults sane.

### Phase 2 — artifact schema + scanner foundation (~2-3hr)

- Migrations: `ruby_sage_scans`, `ruby_sage_artifacts`.
- Models with associations and validations.
- `RubySage::Scanner` walker: respects include/exclude config, computes digests.
- Per-file summarizer (uses configured summarization_model).
- Secret redaction layer.
- Scan metadata: git SHA, versions, file count, errors.
- Locking + atomic write of new scan.
- Retention cleanup.
- Rake task: `rake ruby_sage:scan`.
- Tests against dummy app fixture.

### Phase 3 — retrieval API (~1-2hr)

- `RubySage::Retriever` — keyword + symbol matching over latest scan's artifacts.
- Boost artifacts matching resolved route from `page_context`.
- `POST /ruby_sage/internal/retrieve` endpoint (testable without UI).
- Returns `[{ artifact_id, path, kind, score, snippet }]`.
- Tests: retrieval picks correct artifacts for known queries against dummy app.

### Phase 4 — provider abstraction + chat endpoint (~2hr)

- Fill in Anthropic + OpenAI providers.
- Anthropic: uses `cache_control` on the retrieved-artifact block.
- `POST /ruby_sage/chat` controller: resolves page_context → route → artifacts, calls retriever, builds prompt, calls provider, returns answer + citations.
- Timeout, retry, error handling.
- Tests: end-to-end against a stubbed provider.

### Phase 5 — widget (~2hr)

- HTML partial + helper method `ruby_sage_widget`.
- Vanilla JS: drawer, message thread, page context capture, fetch to `/ruby_sage/chat`.
- Scoped CSS.
- Turbo-safe mount lifecycle.
- CSP nonce on script tags.
- Tests: helper renders, JS smoke test in dummy app.

### Phase 6 — README + landing page + 0.1.0 release prep (~1hr)

- README with install, configure, screenshot, license.
- CHANGELOG.md.
- `gem build` works cleanly.
- CI green.
- Tag `v0.1.0`.

Changemaker integration happens **in the Changemaker repo on a branch**, NOT in ruby_sage. That's its own follow-up task.

## Constraints (non-negotiable)

- Public OSS repo. No proprietary code, schemas, env values, or fixtures derived from real apps land here.
- Gem only. No host-app code in this repo. The `spec/dummy/` app is 100% synthetic.
- Coda commits to feature branches only. Never to `main`. PRs reviewed by Pax before merge.
