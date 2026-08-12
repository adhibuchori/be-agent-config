<!-- Agents live in .claude/agents/ — authoritative list: ls .claude/agents/ -->
<!-- Manual invoke only — no auto-trigger. Call explicitly via the Task tool. -->

| Category | Agent             | Use For                          | Validates / Does                                                            |
| -------- | ----------------- | -------------------------------- | --------------------------------------------------------------------------- |
| Custom   | `agents-reviewer` | Reviewing a modified module      | Layer boundaries, error envelope, query shape, index coverage, file length  |

One agent today, and the index still earns its place: it is what an agent reads
to discover that any agent exists. Add a row when you add a file — a agent that
is not listed here is, in practice, never invoked.
