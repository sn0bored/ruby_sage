# Contributing to RubySage

Thanks for considering a contribution. RubySage is small, opinionated, and aims to stay that way.

## Local development

```bash
git clone git@github.com:sn0bored/ruby_sage.git
cd ruby_sage
bundle install
bundle exec rspec
bundle exec rubocop
gem build ruby_sage.gemspec
```

`.ruby-version` pins development to Ruby 3.3.4. The gem itself supports Ruby 2.7+ — see [Compatibility](#compatibility) below.

The `spec/dummy/` Rails app is what tests run against. It is intentionally minimal and synthetic — please do not add real-world domain code.

## What we welcome

- **Bug fixes** with a regression test.
- **Provider additions** (Cohere, Mistral, local OSS models) — see "Adding a provider" below.
- **Scanner classifier improvements** for paths we don't currently recognize (e.g., GraphQL types, ViewComponents, RSpec factories).
- **Documentation fixes** — broken links, unclear examples, typos.
- **Performance work** with a before/after benchmark.

## What we'd rather you discussed first

Open an issue before sending a PR for any of these:

- New runtime dependencies (we keep the dep tree tight: Rails + Ruby stdlib only for V1).
- Changes to the public API (`RubySage.configuration`, `RubySage.context_for`, controller routes, helper signature).
- Storage layer changes (migrations, model attributes).
- UI redesign of the widget — please check existing UX issues first.

## Compatibility

RubySage supports **Rails 5.2+ / Ruby 2.7+**. That's a deliberate choice: host apps shouldn't have to upgrade just to adopt RubySage. Your code must stay portable:

- No `Data.define`, no shorthand hash-key punning (`{ x:, y: }`), no rightward assignment, no anonymous block forwarding (`&`).
- Be explicit about kwargs at the Ruby 2.7 → 3.0 boundary. Use `**kwargs` consistently.
- No Rails-7-only idioms (`enum :status, [...]` symbol-first form is out — use `enum status: { ... }`).
- No Zeitwerk-only autoload assumptions; classic loader must also work.
- Asset pipeline: Sprockets-only until [#4](https://github.com/sn0bored/ruby_sage/issues/4) lands.

When in doubt, write code that would work in Ruby 2.7 / Rails 5.2 — every newer Ruby/Rails accepts it too. CI verifies cross-version compatibility via a matrix in `.github/workflows/ci.yml`.

## Quality gates

Every PR must pass:

```bash
bundle exec rspec        # all specs
bundle exec rubocop      # zero offenses
gem build ruby_sage.gemspec   # produces a clean .gem
```

PRs that fail any of the three won't be merged.

## Code style

- Every public method has a YARD doc block (params, return, raises, example).
- No magic. No unexplained metaprogramming. Names reveal intent.
- Comments explain WHY, not WHAT. If a method needs a comment to explain WHAT it does, rename or refactor it.
- `snake_case.rb` for Ruby files. Scoped CSS classes under `.ruby-sage-*`.
- Vanilla JS in the widget — no build step, no framework.

## Adding a provider

The most likely contribution path. Pattern:

1. Create `lib/ruby_sage/providers/<name>.rb` inheriting from `RubySage::Providers::Base`.
2. Implement `chat(system_prompt:, cached_context:, messages:, &block)`. Return `{ answer:, citations:, usage: }`.
3. Add the provider to the dispatcher in `lib/ruby_sage.rb` (`RubySage.provider`).
4. Add a spec in `spec/ruby_sage/providers/<name>_spec.rb` using WebMock to stub HTTP.
5. Update `README.md` with a configuration example.
6. Make `chat` accept the optional block (V1.5 streaming-ready) — even if you don't yield to it yet, the signature must accept it.

## Branches and PRs

- Branch naming: `feature/<short-description>`, `fix/<short-description>`, or `docs/<short-description>`.
- Keep PRs small. One concern per PR.
- Reference any related issues in the PR description.
- Squash-merge is the default. Keep your commit messages tidy because they may end up in the merge commit.

## License

By contributing, you agree that your contributions will be licensed under the MIT License (see [LICENSE](LICENSE)).
