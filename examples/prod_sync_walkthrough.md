# Walkthrough: ship a snapshot from CI, never spend tokens in prod

Production should not run scans. Scans cost money (LLM tokens) and add risk
(scan failures shouldn't take down user requests). This walkthrough sets up
"build the snapshot in CI, ship it as a deploy artifact, run it through
`scan:apply` on prod" — the production database has the artifacts, but
production never calls an LLM.

## The plan

1. **CI**: run a scan (or agent-driven scan) to produce `manifest.json` +
   `summaries.json`. Upload as a build artifact.
2. **Deploy**: download the artifact onto the production box. Run
   `bundle exec rake ruby_sage:scan:apply MANIFEST=... SUMMARIES=...`.
3. **Production runtime**: serves the chat widget against the imported scan.
   Zero LLM spend on scans, and the API key is only needed for chat replies
   themselves.

## Option A: classic export/import (V1, API-driven)

If you're OK paying for the scan in CI:

```yaml
# .github/workflows/snapshot.yml
- run: bundle exec rake ruby_sage:scan
  env:
    ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
- run: bundle exec rake ruby_sage:export_artifacts > artifacts.json
- uses: actions/upload-artifact@v4
  with:
    name: ruby_sage_snapshot
    path: artifacts.json
```

Then on the production box (after pulling the artifact down):

```bash
bundle exec rake ruby_sage:import_artifacts < artifacts.json
```

## Option B: agent-driven scan (free, V2 flow)

If your CI runs Claude Code or similar, skip the LLM bill:

```yaml
# .github/workflows/snapshot.yml
- run: bundle exec rake ruby_sage:scan:plan
- run: claude-code --headless --prompt "Read tmp/ruby_sage/INSTRUCTIONS.md and follow it."
- uses: actions/upload-artifact@v4
  with:
    name: ruby_sage_snapshot
    path: tmp/ruby_sage/
```

Then on prod:

```bash
bundle exec rake ruby_sage:scan:apply \
  MANIFEST=$ARTIFACT_DIR/manifest.json \
  SUMMARIES=$ARTIFACT_DIR/summaries.json
```

## Verifying the prod side never calls an LLM at scan time

The applier doesn't import any provider code. To prove it: in production, set
`ANTHROPIC_API_KEY=` (empty) before running `scan:apply`. The apply still
succeeds, the artifacts land, the chat widget works fine for questions (which
do need the key on the production app server, just not on the rake worker).

If your prod chat answers happen on a separate worker tier with the key, you
can keep the key off the web tier entirely.

## When to re-snapshot

A typical pattern:

- **Per merge to main**: re-run the snapshot job in CI. Feature merges land
  fresh artifacts.
- **Daily cron**: catch any out-of-band changes.
- **On deploy**: apply the latest snapshot artifact during the deploy hook.

The applier is fast (DB inserts, no LLM) — re-applying is cheap, so being
generous with how often you sync is fine.
