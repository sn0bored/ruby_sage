# Releasing RubySage

How to publish a new version of `ruby_sage` to [rubygems.org](https://rubygems.org).

**Maintainer-only.** A published gem version is permanent — there is no "delete" button. The only undo is `gem yank`, which removes the version from new installs but doesn't remove it from anyone who already pulled it.

## One-time setup

### 1. RubyGems account

Sign up at [rubygems.org](https://rubygems.org). Use the same email as the gemspec (`dmkwillems@gmail.com`).

### 2. Enable MFA

The gemspec sets `metadata["rubygems_mfa_required"] = "true"`, so MFA is required. In your RubyGems profile, enable a TOTP authenticator (1Password, Authy, or Google Authenticator).

### 3. Create an API key

In `Profile → API Keys → New API Key`:

- Name: `ruby_sage local publish`
- Scopes: `Push rubygem` only. Nothing else.
- Index scope: `Specific Gem` → `ruby_sage`. Limit blast radius.

Copy the API key. You'll be asked for it on first `gem push`.

```bash
mkdir -p ~/.gem
chmod 700 ~/.gem
cat > ~/.gem/credentials <<'EOF'
---
:rubygems_api_key: rubygems_<paste-the-key-here>
EOF
chmod 600 ~/.gem/credentials
```

## Pre-publish checklist

Before pushing any version, verify all of these are true on a clean checkout of `main`:

- [ ] CI is green on `main` (check `.github/workflows/ci.yml` runs).
- [ ] `bundle exec rspec` passes locally.
- [ ] `bundle exec rubocop` passes locally.
- [ ] `gem build ruby_sage.gemspec` produces a valid `.gem` with no warnings.
- [ ] `lib/ruby_sage/version.rb` reflects the version you're about to publish.
- [ ] `CHANGELOG.md` has a section for this version (not just `[Unreleased]`).
- [ ] The README's `[Gem Version]` badge will resolve correctly after push (it will).
- [ ] You've inspected the contents of the built gem at least once:

```bash
gem unpack ruby_sage-X.Y.Z.gem --target=/tmp
ls /tmp/ruby_sage-X.Y.Z/
# Sanity-check no secrets, no spec/, no .github, no PLAN/CLAUDE leakage.
rm -rf /tmp/ruby_sage-X.Y.Z*
```

## Publishing

Run from the repo root, on `main`:

```bash
# 1. Make sure you're up to date.
git checkout main
git pull --ff-only

# 2. Build the gem fresh.
gem build ruby_sage.gemspec
# => ruby_sage-X.Y.Z.gem

# 3. Push.
gem push ruby_sage-X.Y.Z.gem
# Enter MFA code when prompted.

# 4. Tag the release locally and push the tag.
git tag -a vX.Y.Z -m "RubySage vX.Y.Z"
git push origin vX.Y.Z

# 5. Clean up the local .gem artifact.
rm ruby_sage-X.Y.Z.gem
```

Verify on rubygems.org: https://rubygems.org/gems/ruby_sage. The new version should appear within a minute.

Verify it installs cleanly in a fresh project:

```bash
mkdir /tmp/ruby_sage_install_test && cd /tmp/ruby_sage_install_test
bundle init
bundle add ruby_sage
bundle install
# Confirm no resolver errors.
cd ~ && rm -rf /tmp/ruby_sage_install_test
```

## Bumping the version

Semantic versioning: `MAJOR.MINOR.PATCH`.

- **PATCH** (0.1.0 → 0.1.1): bug fix, no API change.
- **MINOR** (0.1.0 → 0.2.0): new feature, backwards-compatible.
- **MAJOR** (0.1.0 → 1.0.0): breaking change. Document the migration.

Edit `lib/ruby_sage/version.rb`, move the `[Unreleased]` block in `CHANGELOG.md` under a new `[X.Y.Z] - YYYY-MM-DD` heading, prepend a fresh empty `[Unreleased]`, commit, then run the publish flow above.

## Yanking a release

If you publish a broken version and need to pull it from the index:

```bash
gem yank ruby_sage -v X.Y.Z
```

This removes the version from new installs but anyone who already downloaded it keeps it. **Yank is not a do-over** — publish a new patch version with the fix instead. Yank only when the version was actively dangerous (security hole, data loss).

## Pre-release versions

For testing major changes, push a pre-release version. RubyGems treats anything with `.alpha` / `.beta` / `.rc` suffixes as pre-release: not installed by default, only when `gem install ruby_sage --pre` or `gem 'ruby_sage', '0.2.0.beta1'` is explicit.

```ruby
# lib/ruby_sage/version.rb
VERSION = "0.2.0.beta1"
```

Publish the same way. Once stable, drop the suffix and publish `0.2.0`.

## What not to do

- **Don't publish from a branch that isn't `main`.** The pushed gem reflects the local working copy, not what's on GitHub.
- **Don't publish without running CI gates first.** A broken release on rubygems is permanent.
- **Don't overwrite a version.** RubyGems forbids it. If you need to fix a published version, bump the patch and publish anew.
- **Don't put secrets in the gemspec or `lib/`.** The published gem is public and forever.

## Future automation

Once releases settle into a rhythm, this can move to a GitHub Actions workflow:

- Trigger on git tag push (`v*`).
- Build, test, then `gem push` using a `RUBYGEMS_API_KEY` secret with the same scoped key.
- For now, manual publish keeps the human in the loop on a high-blast-radius operation.
