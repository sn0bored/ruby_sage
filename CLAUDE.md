# CLAUDE.md — RubySage

Guidance for any Claude/Codex agent working in this repo.

## What this repo is

A Rails engine packaged as the `ruby_sage` gem. Public OSS, MIT-licensed, lives at `sn0bored/ruby_sage`.

## Read this first

`PLAN.md` is the authoritative architecture and build plan. Follow it. If you think the plan is wrong, write your reasoning into your task summary — do not silently deviate.

## Quality bar

We are building this as if it could be merged into Rails core. That means:

- Every public method has a YARD doc block.
- Every behavior has a corresponding RSpec test.
- No magic, no unexplained metaprogramming. Names reveal intent.
- Dependencies kept tight: Rails + Ruby stdlib are enough for V1.
- RuboCop clean and RSpec green are **gates**, not aspirations. CI must be green before declaring a phase done.
- If a method needs a comment to explain WHAT it does, rename or refactor it. Comments explain WHY.

## Compatibility & portability

This gem supports **Rails 5.2+ / Ruby 2.7+**. That's a deliberate choice: host apps shouldn't have to upgrade just to adopt RubySage. To honor it, gem code must stay portable:

- No `Data.define`, no shorthand hash-key punning (`{ x:, y: }`), no rightward assignment, no anonymous block forwarding (`&`).
- Explicit `**kwargs` everywhere — Ruby 2.7 → 3.0 separated kwargs from positional, and we run on both sides of that boundary.
- No Rails-7-only idioms (`enum :status, [...]` symbol-first form is out — use `enum status: { ... }`).
- No Zeitwerk-only autoload assumptions; classic loader must also work.
- Asset pipeline: Sprockets-only for V1.

When in doubt, write code that would work in Ruby 2.7 / Rails 5.2 — every newer Ruby/Rails accepts it too.

## Streaming-ready (don't implement, but don't preclude)

Streaming responses are deferred to v1.5. V1 must not paint us into a corner:
- Provider `chat` method accepts an optional block (ignored in V1, used in v1.5 for incremental yield).
- Chat controller returns JSON in V1 with a shape that's swap-compatible with SSE later.
- Widget JS consumes a single response in V1; v1.5 swaps it to an event stream without redesigning the UI.

## Hard rules

- **Public repo, zero data leakage.** No proprietary code, schemas, env values, or fixtures from any other Lanier/TYB/PollyStop/Changemaker app may land in this repo.
- **`spec/dummy/` is 100% synthetic.** It exists to exercise the engine. No copy-paste from any real app.
- **Gem only.** This repo contains the engine + tests + dummy app + docs. No host-app integration code. Wiring into Changemaker (or any other host) happens in those repos on their own branches.
- **Feature branches only.** Coda never commits to `main`. All work lands on `coda/<descriptor>` branches and goes through review.
- **Tests gate every phase.** Each build phase ends with a passing suite and green CI.
- **No secrets.** Don't commit `.env`, credentials, API keys. The `Anthropic API key` and `OpenAI API key` are read from env at runtime by the host app.

## Style

- Ruby: standard idiom. RuboCop config will land in phase 0.
- JS: vanilla, no build step, no framework.
- CSS: scoped under `.ruby-sage-*`.
- Filenames: `snake_case.rb` for Ruby, `kebab-case.css` is fine.
- No emoji in code or docs unless quoting external content.
