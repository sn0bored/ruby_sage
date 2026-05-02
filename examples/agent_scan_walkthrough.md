# Walkthrough: agent-driven scan

You already pay for Claude Code, Codex, or Cursor. RubySage shouldn't make you
pay a second time to summarize your codebase. This walkthrough shows the
two-step flow that uses your local agent for free.

## What you'll do

1. Generate a manifest of files your scanner found, with redacted contents inlined.
2. Hand the manifest to your coding agent — it writes summaries and audience tags.
3. Apply the summaries. A new completed `Scan` lands in your DB.

Total wall time on a 200-file Rails app: ~2 minutes (mostly your agent's wall time).
RubySage-attributable LLM cost: $0.

## Step 1: plan

```bash
bundle exec rake ruby_sage:scan:plan
```

You'll see something like:

```
Wrote manifest:     /Users/you/your-app/tmp/ruby_sage/manifest.json
Wrote instructions: /Users/you/your-app/tmp/ruby_sage/INSTRUCTIONS.md
Files in manifest:  214 (214 need new summaries)
```

The manifest contains one entry per file with `path`, `kind`, `digest`,
`audiences` (the heuristic default), and `redacted_contents`. Reading it with a
text editor shows you exactly what your agent will see. The instructions file
is a Markdown brief written for the agent.

## Step 2: hand off to your coding agent

Open Claude Code (or your agent of choice) in the same project directory and say:

> Read `tmp/ruby_sage/INSTRUCTIONS.md` and follow it.

The agent reads the manifest, writes a `tmp/ruby_sage/summaries.json` file with
1–2 paragraph summaries per file, and tells you when it's done.

You can also bring your own loop — the contract is just: input is
`manifest.json`, output is `summaries.json` with this shape:

```json
{
  "schema_version": 1,
  "summaries": {
    "app/models/user.rb": "The User model represents a signed-in account..."
  },
  "audience_overrides": {
    "app/views/help/billing.html.erb": ["developer", "admin", "user"]
  }
}
```

`audience_overrides` is optional — use it to expose end-user-facing files to
the `:user` mode without writing a `config.audience_for` callable in your app.

## Step 3: apply

```bash
bundle exec rake ruby_sage:scan:apply
```

```
Scan #14 completed - 214 files, 214 with summaries.
```

The applier creates a `Scan` row plus 214 `Artifact` rows in one transaction.
Files whose digest matches a prior scan reuse the cached summary, so subsequent
runs only ask your agent to do the changed files.

## What you can do now

Open `/ruby_sage/admin/scans` in your browser (signed in as an admin) and
you'll see scan history with artifact counts by kind. Click a scan to browse
its artifacts and read the agent's summaries.

The chat widget will now answer questions grounded in those summaries — e.g.,
"how does the swipe file upload work?" returns an answer with file citations.

## Pre-bake in CI for production

Same flow works for shipping the snapshot to prod (so production never spends
LLM tokens on scans). See [`prod_sync_walkthrough.md`](./prod_sync_walkthrough.md).
