# be-agent-config

A complete AI agent configuration layer for a **backend** repository — rules, hooks, a reviewer
subagent, slash commands, a CI quality gate, and a pipeline that strips the whole thing out of
production branches.

Not a guide about writing rules. The rules themselves, in the form that runs.

Its frontend counterpart is [`fe-agent-config`](https://github.com/adhibuchori/fe-agent-config).

---

## What is actually in here

There are two ways to give an agent rules. One is prose it may or may not read. The other is a
guard that exits non-zero. This repo is mostly the second kind.

| Layer | Files | What it does |
| --- | --- | --- |
| **Router** | `CLAUDE.md` | What to read for which task. Kept short — it is loaded every session |
| **Guardrail** | `AGENTS.md` | Numbered, citable rules, each with an enforcement mechanism named |
| **Contract** | `SSOT.md` | Module structure, layer rules, environment variables |
| **Machine** | `.claude/`, `.mcp.json` | Hooks, the reviewer subagent, anti-patterns, rule tiers |
| **Gate** | `.github/` | The definition of "passing", enforced on every pull request |

Concretely:

- **A migration guard** as a `PreToolUse` hook — a migration that has already run must never be
  edited, and this is the one that blocks rather than warns.
- **12 rule files in two tiers** — `common/` (language-agnostic) and `backend/` (ORM, HTTP
  framework, performance, testing).
- **One reviewer subagent** with a narrow scope, rather than several with overlapping ones.
- **13 slash commands**, maintained once in `_workflow-source/` and mirrored automatically, with
  drift detection.
- **A quality gate** including checks a frontend has no equivalent for: **API spec drift**,
  **migration drift**, **database index coverage**, and **runtime hardening**.
- **An AI-config strip pipeline** so the deployed artifact carries no agent configuration.

---

## How this differs from the frontend layer

Audited rather than assumed, and two of these are the opposite of what people expect:

| | Frontend | Backend |
| --- | --- | --- |
| Rule document | smaller | **larger** |
| Contract document | larger | **much smaller** |
| Rule tiers | four | **two** |
| Subagents | several | **one** |
| Signature hook | generated-output guard, language parity | **migration guard** |
| Signature CI check | translation-key parity | **spec drift, index coverage, runtime hardening** |
| Workflow extension | `.yaml` | **`.yml`** |

**The rule document is longer while the contract is shorter.** Security and data-access rules must
be spelled out; backend architecture is uniform enough that the contract states its shape once.
The practical consequence: do not normalise document length across repos. A backend rule document
as short as a frontend one usually means security rules that were never written down.

That last row looks trivial until you write a script assuming one extension. Match both:

```bash
ls .github/workflows/quality-gate.y*ml
```

---

## What is deliberately not in here

- **No application source.** No `src/`, no schema, no migrations, no lockfile.
- **No secrets, and none required.** Every credential is an environment-variable reference.
- **No `.agents/skills/` mirror.** Design skills have nothing to do in a repo with no interface.

`.agent/workflows/` **is** included — a command mirror for a second tool that reads from that path.
If no such tool is in use, it is a dozen files kept in sync for a reader who does not exist.
Deleting it is a legitimate choice; `SETUP.md` §5 covers the trade-off. Decide knowingly rather
than inheriting it.

---

## Start here

**[SETUP.md](SETUP.md)** — ordered by dependency, roughly an hour. Fill placeholders, wire hooks,
run the gate, and only then touch the strip pipeline.

**[docs/RATIONALE.md](docs/RATIONALE.md)** — why the strange-looking parts are shaped that way.
Read it before you simplify anything.

---

## Two things to know before you clone

**The workflows arrive disarmed.** Every one triggers on `dev` or `prod`, and this repo has only
`main`. Nothing runs on push, and no secrets are needed. They wake up when you create those
branches in your own repo.

**Placeholders are named, never blank.** `<database-name>` rather than an empty string, so
`grep -rn '<[a-z-]*>'` gives you the complete to-do list.

---

## License

MIT. See [LICENSE](LICENSE).
