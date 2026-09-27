<!-- Agents live in .claude/agents/; that folder is the authoritative list. -->
<!-- /review delegates to agents-reviewer; Claude Code may also pick an agent whose description fits. -->

| Category | Agent             | Use For                     | Validates / Does                                                                                   |
| -------- | ----------------- | --------------------------- | -------------------------------------------------------------------------------------------------- |
| Custom   | `agents-reviewer` | Reviewing a modified module | Layer boundaries, error contract, query shape, index coverage, tests, file length, no `any`, one home per identifier |

One agent today, and the index still earns its place: Claude Code finds agents by
their files, but people and commands find them here, with each one's scope in a
line. Add a row when you add a file. `/review` delegates to this one.
