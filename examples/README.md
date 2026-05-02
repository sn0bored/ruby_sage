# RubySage Examples

End-to-end walkthroughs for trying RubySage against a real Rails app. Each
walkthrough is a copy-paste script you run from your host app's root.

| Walkthrough | What it shows |
|---|---|
| [`agent_scan_walkthrough.md`](./agent_scan_walkthrough.md) | Use Claude Code / Codex / Cursor to scan your app — no `ANTHROPIC_API_KEY` needed. |
| [`admin_database_queries_walkthrough.md`](./admin_database_queries_walkthrough.md) | Enable `:admin` mode + the read-only SQL tool, then ask "who is the author of post 47?" |
| [`prod_sync_walkthrough.md`](./prod_sync_walkthrough.md) | Scan in CI, ship the snapshot to prod, never spend tokens in production. |

## Running the examples

Each walkthrough assumes you have:

- RubySage installed (`gem "ruby_sage"` + `rails db:migrate`)
- The `:admin`-gated widget mounted on a layout you can reach signed in as an admin
- Any OS — examples use `bundle exec rake` and `rails runner`, no platform-specific tools

If something doesn't work, the project README has the full configuration
reference. Open an issue if a walkthrough is unclear.

## Sample data

[`sample_summaries.json`](./sample_summaries.json) is a tiny example of the file an
agent produces in the agent-driven scan flow. Useful for understanding the
contract without running an agent yourself.
