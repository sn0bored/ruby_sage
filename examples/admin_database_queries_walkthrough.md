# Walkthrough: admin database queries (the "magic search")

When your client signs in as an admin and asks "who's the author of post 47?",
RubySage can read the schema, write a SQL `SELECT`, run it safely, and answer
in plain English. This walkthrough turns that on.

## Read this first

The `query_database` tool is gated behind a config flag for a reason. The
gem ships with three defense layers:

1. **SELECT-only validation.** `UPDATE`, `DELETE`, `DROP`, `INSERT`,
   `TRUNCATE`, multi-statement queries, and SQL longer than 4KB are rejected
   before they touch the database.
2. **Mandatory transaction rollback.** Every query runs inside a transaction
   that always raises `ActiveRecord::Rollback`. Even if a write somehow
   slipped past validation, it cannot persist.
3. **PostgreSQL `statement_timeout`.** Queries are bounded by `query_timeout_ms`
   (default 5 seconds). Stops a runaway scan from hurting your DB.

The strongest defense the gem cannot give you is a **read-only database
user**. If true tenant isolation matters, set `config.query_connection` to a
connection that points at a role with `SELECT` privileges only. The above
three layers protect against most accidents; a read-only role removes the
trust dependency entirely.

## Step 1: enable the feature

```ruby
# config/initializers/ruby_sage.rb
RubySage.configure do |config|
  config.mode = :admin
  config.enable_database_queries = true

  # OPTIONAL: hard tenant isolation via a read-only connection
  # config.query_connection = ->(_controller) { ReadOnlyDatabase.connection }

  # OPTIONAL: prompt-level multi-tenant scoping reminder
  # config.query_scope = ->(controller) {
  #   "organization_id = #{controller.current_user.organization_id}"
  # }

  # Hard caps (defaults shown)
  # config.max_query_rows           = 100
  # config.query_timeout_ms         = 5_000
  # config.tool_loop_max_iterations = 5
end
```

## Step 2: scan your app

If you haven't already, run a scan so the model has the schema artifact and
your model summaries to work from. Either flow works — the API path:

```bash
bundle exec rake ruby_sage:scan
```

Or the agent-driven path (free, see
[agent_scan_walkthrough.md](./agent_scan_walkthrough.md)):

```bash
bundle exec rake ruby_sage:scan:plan
# (your agent writes summaries.json)
bundle exec rake ruby_sage:scan:apply
```

The schema artifact (`db/schema.rb`) gets tagged for the `developer` and
`admin` audiences automatically.

## Step 3: ask a question

Sign in as an admin (whoever your `auth_check` callable returns true for),
click the floating widget, and try:

> Who is the author of post 47?

Behind the scenes:

1. The chat controller sees `mode == :admin && enable_database_queries == true`
   and builds a tool registry with `query_database` + `describe_table`.
2. The provider receives the tools alongside the artifact context.
3. Claude returns a `tool_use` block requesting `describe_table` for `posts`.
4. The loop dispatches the tool, gets the column list back, and re-issues
   the request with the result appended.
5. Claude returns another `tool_use` requesting `query_database` with a
   `SELECT u.name FROM users u JOIN posts p ON p.user_id = u.id WHERE p.id = 47`.
6. The loop runs the query through `SafeExecutor`, gets back one row.
7. Claude returns a final text answer: "The author of post 47 is Sarah Smith."

The chat response includes `tool_calls` and `iterations` for transparency —
you can show the admin exactly what queries ran:

```json
{
  "answer": "The author of post 47 is Sarah Smith.",
  "tool_calls": [
    { "id": "...", "name": "describe_table", "input": { "table_name": "posts" } },
    { "id": "...", "name": "query_database", "input": { "sql": "SELECT u.name FROM users u JOIN ..." } }
  ],
  "iterations": 3,
  "citations": [...],
  "scan_id": 14,
  "usage": {...}
}
```

## What to watch for

- **Query latency.** Each tool call is one round-trip to your provider plus
  one DB query. A two-step answer is two LLM calls. Budget ~5 seconds per
  question with default settings.
- **Token cost.** A typical "magic search" question is 2-3 LLM calls totaling
  $0.05-$0.20 with Sonnet. Use prompt caching (Anthropic provider does this
  automatically) to amortize the artifact context across questions.
- **Tool loop bound.** `tool_loop_max_iterations` (default 5) caps runaway
  loops. If your model legitimately needs more steps, raise it — but more
  often a higher number masks a bad system prompt.

## Verifying the safety layers

You can test the validation layer at the executor level without going through
the chat loop:

```ruby
executor = RubySage::DatabaseQueries::SafeExecutor.new

# Allowed:
executor.call(sql: "SELECT count(*) FROM users")
# => { columns: ["count"], rows: [[1234]], row_count: 1, truncated: false, ... }

# Rejected before execution:
executor.call(sql: "DELETE FROM users")
# => raises RubySage::DatabaseQueries::SafeExecutor::UnsafeQuery
```

The full safety test matrix is in
[`spec/ruby_sage/database_queries/safe_executor_spec.rb`](../spec/ruby_sage/database_queries/safe_executor_spec.rb).
