# RubySage

[![Gem Version](https://img.shields.io/gem/v/ruby_sage.svg)](https://rubygems.org/gems/ruby_sage)
[![CI](https://github.com/sn0bored/ruby_sage/actions/workflows/ci.yml/badge.svg)](https://github.com/sn0bored/ruby_sage/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Chat with your Rails codebase. Drop in a helper, scan your app, ask questions, get answers grounded in your actual code with citations.

## Why

You've been on a Rails team for six months and nobody can explain how the subscription billing flow works because Steve left in March. You ask the codebase. RubySage answers — with file citations.

## How it works


1. **Scan**: a daily rake task walks your codebase and produces per-file *artifacts* — small structured records with summaries, public symbols, and route mappings. Stored in your app's database. Secret values redacted.
2. **Retrieve**: when someone asks a question, RubySage retrieves the most relevant artifacts (keyword + symbol matching, page-context boosted).
3. **Answer**: the relevant artifacts go into a prompt with the question. The LLM answers, citing the specific files and classes it used.

No giant snapshot stuffed into every prompt. No invented file paths. Just retrieval grounded in your actual code.

## Install

Add to your Gemfile:

```ruby
gem "ruby_sage"
```

Then:

```bash
bundle install
rails generate ruby_sage:install
rails db:migrate
```

Edit `config/initializers/ruby_sage.rb` to set your provider and API key.

## Quickstart

```ruby
# config/initializers/ruby_sage.rb
RubySage.configure do |config|
  config.provider   = :anthropic
  config.api_key    = ENV.fetch("ANTHROPIC_API_KEY", nil)
  config.model      = "claude-sonnet-4-6"
  config.auth_check = ->(c) { c.current_user&.admin? }
end
```

Run your first scan:

```bash
bundle exec rake ruby_sage:scan
```

Drop the widget into your layout:

```erb
<%# app/views/layouts/application.html.erb %>
<body>
  <%= yield %>
  <%= ruby_sage_widget %>
</body>
```

Open your app, click the floating button, ask "what does the PostsController do?". Done.

## Providers

### Anthropic (recommended)

Uses [prompt caching](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching) from day 1. The retrieved-artifact context block carries a `cache_control: ephemeral` marker — subsequent questions within ~5 minutes hit the cache and cost roughly 10× less.

```ruby
config.provider = :anthropic
config.model    = "claude-sonnet-4-6"
config.api_key  = ENV.fetch("ANTHROPIC_API_KEY", nil)
```

### OpenAI

Works fine. No prompt caching in V1.

```ruby
config.provider = :openai
config.model    = "gpt-4.1"
config.api_key  = ENV.fetch("OPENAI_API_KEY", nil)
```

## Running scans

### In development

Run manually after material code changes:

```bash
bundle exec rake ruby_sage:scan
```

Files unchanged since the previous scan are skipped via digest cache, so re-scans are cheap.

### In production

Daily cron is the typical pattern:

```ruby
# config/schedule.rb (using the `whenever` gem) — or your Heroku Scheduler / GitHub Actions cron
every :day, at: "4am" do
  rake "ruby_sage:scan"
end
```

### Pre-bake in CI, ship to prod

Expensive scans don't have to run in production. Bake them in CI:

```yaml
# .github/workflows/snapshot.yml
- run: bundle exec rake ruby_sage:scan
- run: bundle exec rake ruby_sage:export_artifacts > artifacts.json
- uses: actions/upload-artifact@v4
  with:
    name: ruby_sage_snapshot
    path: artifacts.json
```

Then on deploy:

```bash
bundle exec rake ruby_sage:import_artifacts < artifacts.json
```

Production skips LLM summarization entirely — zero token spend on scans.

## Cost

Rough numbers, USD, with Anthropic at current Sonnet pricing. Your mileage will vary by codebase size and question patterns.

| Operation | Frequency | Cost |
|---|---|---|
| Initial full scan (200-file Rails app) | once | ~$0.10–$0.50 |
| Daily incremental scan (50 changed files) | per day | ~$0.05–$0.20 |
| User question (with prompt-cache hit) | per question | ~$0.01–$0.05 |
| User question (cache miss / first of session) | per question | ~$0.10–$0.30 |

Pre-baking in CI moves the daily-scan cost off your production token budget entirely.

## AI agent integration

RubySage's retrieval layer is a public Ruby API, not just a widget. Wire it into Cursor, Claude Code, Codex, or your own coding agent to give the model indexed knowledge instead of dumping the whole codebase into context.

```ruby
result = RubySage.context_for("how does subscription billing work?")

result[:artifacts]   # => relevant Artifact records
result[:citations]   # => [{path:, kind:, score:, snippet:}, ...]
result[:scan_id]     # => Scan id used
```

Or hit the JSON endpoint:

```bash
curl -X POST https://your-app.com/ruby_sage/internal/retrieve \
  -H "Content-Type: application/json" \
  -d '{"query":"subscription billing"}'
```

A typical Cursor / Claude Code session can spend 50–200K input tokens orienting the model to a Rails codebase before any real work happens. Swap that for a 3K-token retrieval call and your dev token bill drops by an order of magnitude.

## Configuration reference

```ruby
RubySage.configure do |config|
  # Provider
  config.provider             = :anthropic         # :anthropic | :openai
  config.api_key              = ENV.fetch("ANTHROPIC_API_KEY", nil)
  config.model                = "claude-sonnet-4-6"
  config.summarization_model  = "claude-haiku-4-5"

  # Authorization (server-side, enforced before_action)
  config.scope                = :admin             # :admin | :signed_in | :public_rate_limited
  config.auth_check           = ->(c) { c.current_user&.admin? }

  # Optional CSP nonce hook
  config.csp_nonce            = ->(c) { c.content_security_policy_nonce }

  # Scanner
  config.scanner_include      = [...] # see lib/ruby_sage/configuration.rb for defaults
  config.scanner_exclude      = [...]
  config.scan_retention       = 7

  # HTTP
  config.request_timeout      = 30
  config.max_retries          = 2
end
```

## Security

- **Server-side auth.** Every chat / retrieve request goes through `before_action :authorize_ruby_sage!`. The widget UI is just UX; the endpoint is the gate.
- **Secret redaction.** YAML values for keys matching `(api_key|secret|password|token|access_key|private_key|client_secret)` are replaced with `[REDACTED]` at scan time. `ENV[...]` symbol references are preserved (the model needs to know which dependencies exist), but values never are. `credentials.yml.enc` is excluded entirely.
- **Provider data policies.** Anthropic and OpenAI receive your code summaries (not raw source by default) when you ask questions. Read each provider's data retention policies before scanning sensitive code.
- **Older Ruby/Rails.** RubySage supports Rails 5.2+ / Ruby 2.7+ to avoid forcing host-app upgrades, but Ruby 2.7 and Rails 5.2/6.x are EOL. If you're on EOL Ruby/Rails, your app's security exposure is on you — please upgrade when you can.

## Compatibility

- **Ruby**: 2.7+
- **Rails**: 5.2+
- **Database**: anything ActiveRecord supports (PostgreSQL, MySQL, SQLite tested).

CI tests across the matrix. See `.github/workflows/ci.yml`.

## Roadmap

- v1.5: streaming responses (SSE), Propshaft asset pipeline, optional pgvector embeddings.
- v2: hosted RubySage Cloud — shared snapshots across dev/prod environments, no token spend on your end.

## Contributing

Pull requests welcome. Run `bundle exec rspec` and `bundle exec rubocop` before opening one. Code must stay portable to Ruby 2.7 / Rails 5.2.

## License

MIT. See [LICENSE](LICENSE).
