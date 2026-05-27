# RubySage — Next Steps (lean V1, post-2026-05-27 decisions)

Status: planning, locked. Picked up after comparing RubySage to [vexp.dev](https://vexp.dev/) and a 2026-05-27 Telegram conversation that narrowed the scope.

## What changed on 2026-05-27

Earlier drafts framed RubySage as a "two-faced" product (widget + MCP). After talking it through, that's overbuilt. Decisions:

- **The pivot point is the MCP, not the widget.** The widget already does what end users need (chat over FAQs). No new investment there.
- **Single gem, one story.** `ruby_sage` becomes a codebase-context MCP. The widget ships in the same gem, maintenance-only. Bundling supports a cleaner LinkedIn / customer narrative: "RubySage is how I optimize my dev workflow across all my Rails apps."
- **Lean V1.** Structural extraction only — no LLM summaries, no dependency graph, no pivot/skeleton retriever in V1. Those are V1.5+ if they earn their keep.
- **The "dynamic DB report" thing users want (who signed up last, etc.) is a separate product.** Do not let it leak into this scope.

This is a personal-leverage tool first. Goal: when Pax (or any coding agent) opens one of Daniel's Rails repos — ChangeMaker, AIT/Hub, NA Travel, TYB server — it can ask "what handles /foo?" or "show me the User model surface" without walking the whole repo with grep/read. Token savings, faster pickup, no $20/mo per-tool subscription.

## TL;DR

`gem 'ruby_sage'` + a generator gives you:

1. **`.ruby_sage/` on disk** — signatures, routes, file metadata. Source of truth.
2. **`bin/ruby_sage mcp`** — stdio MCP server, no Rails boot, reads disk.
3. **File watcher** — re-scans on change.
4. **Existing widget** — unchanged, queries DB index rebuilt from disk.

Coding agents (Claude Code, Cursor, anything MCP-aware) get cheap structural answers about your repo without re-walking it every session.

## Architecture

```
host-app/
├── .ruby_sage/
│   ├── manifest.json              ← scan metadata (sha, ruby/rails versions, file count)
│   ├── artifacts/
│   │   └── app/models/user.rb.yml ← signatures + digest
│   ├── routes.json                ← route → controller#action → file
│   └── .gitignore
├── app/
└── ...
```

- Widget queries DB (rebuilt from disk via `ruby_sage index`). Interface unchanged from today.
- MCP server reads disk directly. No Rails required.
- File watcher (in MCP) triggers incremental rescans on change.
- Digests gate re-extraction — same file → cache hit.

What's **not** in V1: LLM summaries, dependency graph, pivot/skeleton retrieval. The artifact layer is designed so these can be added incrementally without rework.

## Phases (lean V1)

### Phase A — Quick vexp recon (~half day)
- Install vexp on ChangeMaker, observe its MCP tool surface.
- Note tool names, schemas, descriptions, and which tools the agent actually picks up under load.
- Output: `notes/vexp-mcp-surface.md` — their tools + our equivalents.
- Reason for doing this: cheap insurance against naming our tools in a way that re-trains agent muscle memory poorly.

### Phase B — Disk-backed artifact layer (~2-3 days)
- Refactor `RubySage::Scanner` to write `.ruby_sage/` on disk.
- DB models become a derived index.
- `ruby_sage index` (subcommand) rebuilds DB from disk.
- Widget continues querying DB. No widget code changes.

### Phase C — Prism-based signature extraction (~2 days)
For each Ruby file: class/module declarations + ancestry, public method signatures (name, arity, kwargs, defaults), AR associations + validations + enums + scopes, includes/extends/prepends, top-level constant references.
For `config/routes.rb`: existing Rails routes loader → `routes.json`.

No LLM in this phase. Pure structural.

### Phase D — MCP server (~2-3 days)
`bin/ruby_sage mcp` — stdio MCP server, no Rails boot. V1 tools:

| Tool | Purpose |
|---|---|
| `find_relevant_files` | Query → file list with match reasons (symbol hits, route hits) |
| `get_file_context` | path + mode (`full` / `signature`) |
| `get_route_handler` | URL → handler file (Rails edge) |
| `search_symbols` | Exact-match symbol lookup |

Tool surface intentionally smaller than the earlier draft. Add more after watching real agent usage.

File watcher (`listen` gem) triggers incremental rescans.

### Phase E — Install generator (~1 day)
`rails generate ruby_sage:install`:
1. Drop `config/initializers/ruby_sage.rb` with defaults.
2. Run widget DB migration.
3. Create `.ruby_sage/` + `.gitignore`.
4. Run initial scan.
5. Print MCP install instructions + copy-pasteable `.claude.json` snippet.
6. `--with-claude-config` flag writes `.claude.json` directly.

### Phase F — Multi-repo rollout (Daniel, post-ship)
Order: **ChangeMaker** (biggest stress test) → **AIT/Hub** + **NA Travel** → **TYB server**.

Non-Rails repos (TYB Mobile, Daily Neon Mobile, PollyStop frontend) are **out of scope for V1**. Language-agnostic via tree-sitter is roadmap, not now.

## CLI shape

Single binary, subcommands (not separate binaries):

```
ruby_sage scan      # one-shot scan, writes .ruby_sage/
ruby_sage index     # rebuild widget DB from .ruby_sage/
ruby_sage mcp       # start stdio MCP server
ruby_sage init      # alias for `rails generate ruby_sage:install`
```

## V1.5+ candidates (not now)

These were in earlier drafts and are deferred until V1 proves the artifact-layer pattern earns its keep:

- LLM summaries per file (digest-cached). Cost: ~$0.50 to summarize a 500-file Rails repo at Haiku rates.
- Dependency graph (`graph.json`) with edges from AR associations + constant refs + route mappings.
- `RubySage::Retriever#call(query, page_context:, budget:)` — pivot/skeleton retrieval with token budget awareness.
- `list_recent_changes` MCP tool — what changed since timestamp/sha.
- Tree-sitter for non-Ruby repos.

## Hard rules (carry over from CLAUDE.md)

- Public repo, zero data leakage. No proprietary code, schemas, or fixtures from any other application.
- `spec/dummy/` is 100% synthetic.
- Rails 5.2+ / Ruby 2.7+ portability. No `Data.define`, no hash-key punning, no rightward assignment, explicit `**kwargs`.
- RuboCop clean + RSpec green are gates.
- Streaming-ready without implementing it (provider `chat` accepts optional block).

## How to resume

This file is the resume point. Don't need to re-explain the architecture or the pivot — it's all here.

When picking up:
- Start Phase A unless you've already done it.
- Move to Phase B once vexp recon notes are written.
- Old `PLAN.md` is superseded for Phases 2–6 but the gem-skeleton/engine-shell/config phases (0–1) in `PLAN.md` still apply for any setup that hasn't shipped yet.

## Decisions log (for posterity)

- **2026-05-27** — Locked single-gem bundling (not splitting `ruby_sage_mcp`), widget frozen as-is, V1 scope cut to structural extraction only, deferred LLM summaries + graph + retriever, dynamic-DB-report use case parked as separate future product.
