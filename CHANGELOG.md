# Changelog

## [Unreleased]

- Phase 5: Widget helper + partial, vanilla JS drawer with page-context capture, scoped CSS, Turbo-safe mount lifecycle, CSP nonce support, csp_nonce config hook.
- Phase 4: Anthropic + OpenAI providers (Net::HTTP, no new deps), Anthropic prompt caching via cache_control, chat controller with retrieval-and-citations response shape, error handling for provider failures and missing params.
- Phase 3: Retriever (keyword + symbol scoring with page-context boost), internal /retrieve endpoint, RubySage.context_for convenience entry point.
- Phase 2: Artifact schema (ruby_sage_scans + ruby_sage_artifacts), Scanner walker with classification + symbol extraction, Summarizer (graceful fallback when no API key), SecretRedactor, file-based locking, retention cleanup, rake ruby_sage:scan task.
- Phase 1: Configuration object, server-side authorization, asset pipeline + CSP nonce hook, provider abstraction interface, health endpoint.
- Phase 0: gem skeleton, dummy host app, RSpec setup, RuboCop, CI.
