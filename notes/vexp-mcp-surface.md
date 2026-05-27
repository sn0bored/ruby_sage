# vexp MCP surface recon

Date: 2026-05-27

Sources checked: <https://vexp.dev/docs>, <https://vexp.dev/changelog>, <https://chat.mcp.so/server/vexp>, and GitHub search for public vexp MCP source/manifests. I found vexp's public docs and benchmark repo, but not a public MCP `tools/list` manifest or server source. Treat the schemas below as the documented parameter surface, not verified raw JSON Schema. Exact agent-visible description strings could not be verified beyond the public docs wording.

## Vexp tool surface

vexp documents 11 MCP tools.

| Tool | One-line purpose | Documented input schema | Public docs description visible to agents |
| --- | --- | --- | --- |
| `run_pipeline` | Single-call task context, impact, and memory pipeline. | `task: string`; `preset: "auto" \| "explore" \| "debug" \| "modify" \| "refactor" = "auto"`; `max_tokens: number = 10000`; `include_tests: boolean = false`; `include_file_content: boolean = true`; `observation: string`; `repos: string[] = all` | Primary tool. Combines context search, impact analysis, and memory recall; auto-detects intent; returns compressed output with expandable V-REF hashes. |
| `get_context_capsule` | Return relevant code for a task. | `query: string`; `repos: string[] = all`; `max_tokens: number = 8000`; `pivot_depth: number = 2`; `include_tests: boolean = false`; `skeleton_detail: "minimal" \| "standard" \| "detailed" = "standard"` | Returns pivot files in full and supporting files as skeletons; auto-includes relevant prior memories; docs say to use before code changes. |
| `get_impact_graph` | Show dependents affected by changing a symbol. | `symbol_fqn: string`; `depth: number = 5`; `cross_repo: boolean = true`; `format: "list" \| "tree" \| "mermaid" = "tree"` | Shows code that would break or be affected if a symbol changes; intended before refactors or public API changes. |
| `search_logic_flow` | Find execution paths between two symbols. | `start: string`; `end: string`; `max_paths: number = 3`; `cross_repo: boolean = true` | Finds data/control-flow paths from one fully-qualified symbol to another through the call graph. |
| `get_skeleton` | Return compact signatures for files. | `files: string[]`; `detail: "minimal" \| "standard" \| "detailed" = "standard"`; `repo: string = primary repo` | Returns token-efficient file skeletons: signatures, class declarations, and type definitions without implementation bodies. |
| `index_status` | Report index health and progress. | No parameters documented. | Returns file count, node count, edge count, daemon uptime, and indexing progress. |
| `workspace_setup` | Help configure vexp for a workspace. | No parameters documented. | Onboarding tool that detects installed agents, generates config files, and returns a workspace template. |
| `get_session_context` | Return current or prior session observations. | `include_previous: boolean = false`; `max_results: number = 50` | Returns observations with stale flags and chronological ordering, covering what the agent explored and decided. |
| `search_memory` | Search cross-session observations. | `query: string`; `max_results: number = 10` | Hybrid memory search using relevance, similarity, recency, and graph proximity, including a ranking explanation. |
| `save_observation` | Persist an insight, decision, error, or manual note. | `content: string`; `type: "insight" \| "decision" \| "error" \| "manual" = "manual"`; `linked_symbols: string[]` | Saves observations with optional symbol links; linked memories can be marked stale when code changes. |
| `expand_vexp_ref` | Expand compressed pipeline references. | `hash: string` documented as a 12-hex-character V-REF hash | Internal tool for expanding `[V-REF:xxxx]` hashes from `run_pipeline` output into full code content. |

## Our equivalents (proposed)

| RubySage Phase D tool | Closest vexp equivalent | Naming call | Reason |
| --- | --- | --- | --- |
| `find_relevant_files` | `get_context_capsule` / `run_pipeline` | Stay as-is for V1. | RubySage V1 returns a ranked file list with match reasons, not a full capsule or pipeline result. |
| `get_file_context` | `get_skeleton` for `signature` mode; no exact full-file equivalent except capsule pivots | Stay as-is. | One tool covering `full` and `signature` modes is clearer for Rails agents than splitting skeleton and content fetches. |
| `get_route_handler` | None visible. | Deliberately diverge. | Rails route-to-controller lookup is RubySage's framework-specific edge and should be explicit. |
| `search_symbols` | No exact equivalent; vexp has FQN consumers such as `get_impact_graph`. | Stay as-is. | Exact symbol lookup is a cheap structural primitive and avoids pretending RubySage has vexp's graph traversal. |

## Surface-area gaps

Vexp-only:

- `run_pipeline`: consider for V1 only as a thin orchestration wrapper if the first-pass tools feel too chatty.
- `get_context_capsule`: consider for V1 as a future alias/wrapper once RubySage returns file content plus signatures in one response.
- `get_impact_graph`: deferred; requires a dependency graph, listed in `NEXT.md` as V1.5+.
- `search_logic_flow`: deferred; requires call graph/control-flow extraction.
- `get_skeleton`: consider for V1 naming only; RubySage's `get_file_context(mode: "signature")` covers the core behavior.
- `index_status`: consider for V1; cheap status over `.ruby_sage/manifest.json` and scan freshness.
- `workspace_setup`: out of scope; RubySage setup belongs in `rails generate ruby_sage:install` and CLI output.
- `get_session_context`, `search_memory`, `save_observation`: deferred; session memory is outside lean V1.
- `expand_vexp_ref`: out of scope unless RubySage adopts compressed references.

RubySage-only:

- `get_route_handler`: consider for V1; this is the Rails-specific lookup vexp does not expose.
- `search_symbols`: consider for V1; exact structural lookup fills the gap between route lookup and natural-language file search.
