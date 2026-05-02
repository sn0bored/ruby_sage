# RubySage Cloud — v2 product sketch

> Status: design doc, not code. This is the "what would the hosted version
> look like" thinking that informs how the OSS gem gets architected today.

The OSS gem is the entire wedge: a Rails team installs it, it works, they get
value. The Cloud product makes the same gem more useful for teams and
consultants by removing operational friction (no migrations, no scan
scheduling, no DB clutter) and adds team-level features (cross-repo search,
usage dashboard, white-label).

This doc sketches:

1. The user journeys we're solving for
2. The hosted architecture
3. The pricing model
4. The OSS-to-Cloud migration path
5. What we need to build first

## User journeys

### "Solo Rails developer with a side project"

Wants the chat widget on her side project but doesn't want to run a scan
cron, doesn't want LLM bills she has to monitor, doesn't want a new schema
migration on a freshly-deployed app. Free tier handles ~100 questions/month
on one repo. Sign up, paste a token, done.

### "5-person team at a Series A"

Wants the widget shared across the team, wants to see who's asking what (for
both audit and "huh, three people asked about billing this week, maybe we
should write docs"), wants the snapshot to stay fresh without anyone owning
it, wants to budget the cost. Team tier with usage dashboard and a fixed
monthly cap.

### "Consulting shop building 4 client apps"

(This is Daniel.) Wants to install the same gem in every client app he ships,
wants ONE place to see all clients' usage, wants the option to white-label
the widget per client, wants to bill clients separately. Consultant tier with
multi-tenant management and per-client API tokens.

### "End-user-facing app at a public-facing company"

Wants the `:user` mode widget on the marketing/help pages, expects high
volume, wants high reliability, wants no leak of internals. Enterprise tier
with SLA, audit log, hosted in the customer's region.

## Hosted architecture

```
┌─────────────────────┐         ┌──────────────────────────────┐
│ Host Rails app      │         │ RubySage Cloud (Rails app)   │
│                     │         │                              │
│ + ruby_sage gem     │ HTTPS   │ ┌──────────────────────────┐ │
│ + cloud_token       ├────────▶│ │ Snapshots API            │ │
│ + widget            │         │ │ POST /v1/snapshots       │ │
│                     │         │ │ - accepts manifest+sums  │ │
│ Chat: provider ─────┤         │ │ - stores per-repo        │ │
│   :ruby_sage_cloud  │         │ └──────────────────────────┘ │
└─────────────────────┘         │ ┌──────────────────────────┐ │
                                │ │ Retrieval API            │ │
                                │ │ POST /v1/retrieve        │ │
                                │ │ - keyword + pgvector     │ │
                                │ └──────────────────────────┘ │
                                │ ┌──────────────────────────┐ │
                                │ │ Chat API                 │ │
                                │ │ POST /v1/chat            │ │
                                │ │ - retrieves              │ │
                                │ │ - calls upstream LLM     │ │
                                │ │ - meters usage           │ │
                                │ └──────────────────────────┘ │
                                │ ┌──────────────────────────┐ │
                                │ │ Dashboard (web UI)       │ │
                                │ │ - usage charts           │ │
                                │ │ - question history       │ │
                                │ │ - repo management        │ │
                                │ │ - team members           │ │
                                │ └──────────────────────────┘ │
                                └──────────────────────────────┘
```

### Snapshot ingestion

The host's CI runs the existing `scan:plan` + `scan:apply` flow but with the
applier writing to Cloud instead of the local DB:

```ruby
# config/initializers/ruby_sage.rb
RubySage.configure do |config|
  config.backend = :cloud
  config.cloud_token = ENV["RUBYSAGE_CLOUD_TOKEN"]
end
```

A new `RubySage::Backends::Cloud` swaps the local `Scan` / `Artifact`
ActiveRecord models for an HTTP client. The widget and chat controller don't
care which backend is active.

### Retrieval

The OSS retriever stays for self-hosted users. The Cloud backend implements
the same `RubySage::Retriever` interface but HTTPs to `/v1/retrieve`. Plus
pgvector embeddings for semantic search (deferred from OSS v1.5).

### Chat

The Cloud's `/v1/chat` accepts messages, retrieves, calls the upstream LLM
(Anthropic or OpenAI per the plan tier), meters tokens, and returns the
answer. The host app never sees an Anthropic API key.

For the `:admin` tool flow: the host needs the SafeExecutor to run locally
(it touches the local DB), but the LLM tool-call orchestration happens in
Cloud. The Cloud chat API streams back the SQL the model wants to run; the
host's local executor runs it; the host posts the result back. One extra
round-trip, but the host's DB is never exposed to Cloud.

### Auth

Per-repo API tokens (`rsk_live_...`). Tokens map to a billing account and
plan tier. Created in the dashboard, scoped to one repo.

## Pricing

Usage-based on questions, not seats. Predictable bills, scales naturally,
matches what the user perceives as "value" (questions answered).

| Tier | Price | Questions/mo | Repos | Audience |
|---|---|---|---|---|
| Free | $0 | 100 | 1 | Hobbyist trying it |
| Hobby | $10 | 1,000 | 3 | Side projects, indie devs |
| Team | $50 | 10,000 | unlimited | 5–20 person teams |
| Consultant | $200 | 50,000 | unlimited, white-label | Dev shops with multiple clients |
| Enterprise | custom | custom | custom | SLA, region pinning, SSO |

Overages: $0.01/question after the cap, capped at the next tier's price.

LLM cost basis: Sonnet questions cost ~$0.05–0.30 each at retail. We mark up
~3–5x after caching effects, plus we get bulk pricing, plus we amortize
fixed infra. Free tier is loss-leader.

## OSS-to-Cloud migration

A signed-up user can opt into Cloud without ripping out the gem:

1. Generate a Cloud token in the dashboard.
2. Add `config.backend = :cloud` to the initializer.
3. (Optional) `bundle exec rake ruby_sage:cloud:migrate` to push existing
   local snapshots up to Cloud.
4. (Optional) `rails db:rollback STEP=N` to drop the local
   `ruby_sage_*` tables.

Going back is symmetric: `config.backend = :local`, run migrations, run a
fresh local scan.

## What we'd build first

In priority order — each step is independently shippable:

1. **`RubySage::Backends` abstraction in OSS gem.** Refactors the local-DB
   path behind a `Backends::Local`. Sets up the seam for `Backends::Cloud`
   without building the cloud yet. (~1 week, fits in v1.2 of the gem.)
2. **Cloud Rails app skeleton.** Auth, billing scaffold (Stripe), API
   tokens, snapshots ingestion endpoint, dashboard with usage charts.
   (~3-4 weeks.)
3. **`Backends::Cloud` in OSS gem.** HTTP client implementing the same
   interface as `Backends::Local`. Ship under a feature flag. (~1 week.)
4. **Retrieval and chat APIs in Cloud.** Includes pgvector embeddings.
   (~2 weeks.)
5. **Dashboard polish, white-label, audit log.** (~2 weeks.)
6. **Beta launch** with 10 hand-picked Rails teams. Free for 3 months in
   exchange for feedback.

Total: ~10 weeks to a credible v2 launch.

## Open questions

- **Self-hosted Cloud edition?** Some enterprises want the dashboard but
  need data residency. Worth offering at the Enterprise tier as a Docker
  Compose bundle.
- **GitHub App for auto-scan?** "Connect your repo" flow that runs scans on
  every push, no CI config needed. Attractive but requires us to clone the
  repo (security considerations).
- **Embeddings provider lock-in.** OpenAI's `text-embedding-3-large` is
  cheap and good. Voyage's code-specialized embeddings might be better. We
  want to be able to swap.
- **Cross-repo search at the Consultant tier.** "Search across all my
  client apps for who uses Stripe" is a killer feature for consultants but
  needs careful tenant boundary thinking.

## Why this is the right time

The OSS gem proves three things matter that didn't six months ago:

1. **Tool-using LLMs work well enough for production.** Phase C's database
   query loop wasn't possible in 2025 with the available models.
2. **Coding agents (Claude Code, Codex, Cursor) are mainstream.** The
   agent-driven scan flow is now valuable to most users instead of a
   curiosity. That removes the LLM-cost objection from the install story.
3. **Rails teams are tired of "ChatGPT for code" tools that don't actually
   know their code.** Cursor's codebase chat is generic; RubySage knows
   your routes, your service objects, your schema. That specificity is the
   moat.
