# Changelog

## [Unreleased]

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
