<div align="center">

# be-agent-config

**A complete, runnable AI agent configuration layer for a backend repository.**

Rules, a blocking migration guard, a scoped reviewer subagent, slash commands, a 15-step CI quality
gate with spec-drift and index-coverage checks, and a pipeline that strips the entire layer out of
production branches.

Not advice about writing rules. The rules themselves, in the form that executes.

[Setup](SETUP.md) · [Rationale](docs/RATIONALE.md) · [Frontend](https://github.com/adhibuchori/fe-agent-config) · [Docs site](https://github.com/adhibuchori/docs-agent-config)

</div>

---

## Table of contents

- [The problem this solves](#the-problem-this-solves)
- [The four layers](#the-four-layers)
- [What ships](#what-ships)
- [How a backend layer differs from a frontend one](#how-a-backend-layer-differs-from-a-frontend-one)
- [Repository structure](#repository-structure)
- [Quick start](#quick-start)
- [What is deliberately excluded](#what-is-deliberately-excluded)
- [Requirements](#requirements)
- [Adapting it to your stack](#adapting-it-to-your-stack)
- [Design decisions worth knowing before you edit](#design-decisions-worth-knowing-before-you-edit)
- [FAQ](#faq)
- [License](#license)

---

## The problem this solves

Most AI agent configuration is prose. You write `AGENTS.md`, list your conventions, and hope the
agent reads it. Some days it does.

Prose has no failure mode. When a rule is ignored, nothing reports it — the code just lands. So the
rule quietly becomes a suggestion, and the document becomes something people stop maintaining
because it stopped mattering.

On a backend the stakes are different in kind, not just degree. A frontend mistake renders wrong; a
backend mistake edits a migration that has already run, and the damage appears one environment
later. **This is why the backend layer leans harder on hooks that block than on documents that
advise.**

Every convention here is attached to something that exits non-zero — a hook that stops the tool
call, a gate step that fails the pull request, or an explicitly labelled `advisory` when no
mechanism exists. Nothing sits in between, unenforced and assumed.

---

## The four layers

| Layer | File | Job | Size |
| :-- | :-- | :-- | --: |
| **Router** | `CLAUDE.md` | What to read for which task. Loaded every session, so kept short | 158 lines |
| **Guardrail** | `AGENTS.md` | Numbered, citable rules, each naming its enforcement mechanism | 496 lines |
| **Contract** | `SSOT.md` | Module structure, layer rules, environment variables | 108 lines |
| **Machine** | `.claude/`, `.mcp.json` | Hooks, reviewer subagent, anti-patterns, rule tiers | 32 files |
| **Gate** | `.github/` | The definition of "passing", enforced on every pull request | 4 workflows |

Note the shape: the guardrail is three times the size of the router and nearly five times the
contract. That is correct for a backend and is explained below.

---

## What ships

### The migration guard

The single most important hook here, and the clearest case for `PreToolUse`:

```bash
if [[ "$FILE" =~ (^|/)(migrations|drizzle)/.*\.(sql|ts)$ ]]; then
  echo "[migration-guard] BLOCKED: $FILE is a migration. Create a new one instead." >&2
  exit 1
fi
```

A migration that has already run must never be edited — change it and the migration history differs
between environments, damage that surfaces only when the next environment deploys. The correct fix
is always the same and always safe: **create a new migration.**

`PreToolUse` matters specifically because a non-zero exit there stops the tool call *before it
happens*. In `PostToolUse` the write has already landed and the hook is merely a complaint.

### Rules — 12 files across 2 tiers

```
.claude/rules/
├── common/     8 files   language-agnostic — transfers as is
└── backend/    4 files   ORM, HTTP framework, performance, testing
```

Two tiers, not four. Backend architecture is uniform enough that one domain tier carries it.

### Reviewer subagent — one, not several

`be-reviewer` checks layer boundaries, the error contract, database rules, and query performance
against the numbered rules in `AGENTS.md`. One agent with a real rulebook beats several with
overlapping mandates.

### Quality gate — 15 steps

Four have no frontend equivalent:

| Step | Catches |
| :-- | :-- |
| **API spec drift** | Regenerates the spec and fails if the committed file changed — a route altered without updating the contract |
| **Migration drift** | Schema and migrations have diverged |
| **Index coverage** | A frequently filtered column has no index. Usually advisory |
| **Runtime hardening** | Timeouts, pool limits, and similar production settings are present |

**Wire spec drift first if you wire only one.** The committed spec is your only cross-repo
contract, and consumers generate their clients from it. Without this check the contract degrades
quietly and the cost lands in someone else's repository.

> **Name collision worth flagging.** "Index coverage" here means **database indexes**. Elsewhere in
> this configuration, "index coverage" means `INDEX.md` files listing commands and rules. Both
> checks can run in the same gate.

The remaining eleven: format · lint · type check · comment style · comment block length · workflow
mirror drift · AI config rule drift · security audit · `.env` not committed · secret scan ·
production build.

### Slash commands — 13, maintained once

Sources live in `_workflow-source/` and are mirrored into `.claude/commands/` and
`.agent/workflows/` by `scripts/sync-workflows.sh`, with drift detection in `--check` mode.

### AI-config strip pipeline

Four scripts that remove this entire layer from the production branch. `strip-paths.sh` is the
single source of truth for what gets removed; the other three source it rather than copying it.

---

## How a backend layer differs from a frontend one

Audited by counting, not assumed. Two of these are the opposite of what people expect.

| | Frontend | Backend |
| :-- | :-- | :-- |
| Rule document | 335 lines | **496 lines — larger** |
| Contract document | 309 lines | **108 lines — much smaller** |
| Rule tiers | 4 | **2** |
| Subagents | 4 | **1** |
| Signature hook | generated-output guard, language parity | **migration guard** |
| Signature CI check | translation-key parity | **spec drift, index coverage, runtime hardening** |
| Workflow extension | `.yaml` | **`.yml`** |
| Skill mirror | present | **absent by design** |

**The rule document is longer while the contract is shorter.** Security and data-access rules must
be spelled out — "validate input at system boundaries" cannot be compressed into one actionable
sentence; it needs the boundary list and the failure behaviour. Meanwhile backend architecture is
uniform enough that the contract states its shape once.

The practical consequence: **do not normalise document length across repositories.** A backend rule
document as short as a frontend one usually means security rules that were never written down.

That last row on file extensions looks trivial until you write a script assuming one of them. Match
both:

```bash
ls .github/workflows/quality-gate.y*ml
```

---

## Repository structure

```
be-agent-config/
├── CLAUDE.md                    Router — what to read for which task
├── AGENTS.md                    Guardrail — numbered rules + compliance status table
├── SSOT.md                      Contract — module structure, layer rules, environment
├── SETUP.md                     Ordered installation guide
├── LICENSE                      MIT License
├── .mcp.json                    11 MCP servers, neutral env-var names
│
├── .claude/
│   ├── settings.json            Hook wiring, permission allow/deny lists
│   ├── rules/                   12 files · common → backend
│   ├── agents/                  be-reviewer.md
│   ├── anti-patterns/           2 documented failures + INDEX.md
│   ├── hooks/                   4 scripts + lib.sh — migration-guard.sh is the key one
│   ├── commands/                13 slash commands (generated)
│   └── *.example.md             3 optional shared docs — fill in or delete
│
├── .agent/workflows/            Command mirror for a second tool (generated)
├── _workflow-source/            13 command sources + INDEX.md — edit here
│
├── scripts/
│   ├── sync-workflows.sh        Mirror commands, with --check drift mode
│   ├── check-migrations.sh      Schema-vs-migration drift
│   └── check-index-coverage.sh  Database index coverage
│
├── .github/
│   ├── workflows/               quality-gate · ci · ci-cd · strip-ai-on-pr
│   ├── scripts/                 quality-gate.sh · strip-paths.sh · strip-ai.sh
│   │                            verify-strip.sh · back-merge-prod.sh
│   │                            check-comment-blocks.sh · check-comment-style.ts
│   └── pull_request_template.md
│
└── docs/RATIONALE.md            Why the odd-looking parts are shaped that way
```

**91 files. No application source code.**

---

## Quick start

```bash
git clone https://github.com/adhibuchori/be-agent-config.git
cd your-project

CFG=../be-agent-config
cp -R "$CFG"/{.claude,.agent,_workflow-source,.github,scripts} .
cp "$CFG"/{CLAUDE.md,AGENTS.md,SSOT.md,.mcp.json} .

# Placeholders are named, never blank — this is your complete to-do list
grep -rn '<[a-zA-Z][a-zA-Z -]*>' CLAUDE.md AGENTS.md SSOT.md .mcp.json .claude/

chmod +x .claude/hooks/*.sh
```

Then follow **[SETUP.md](SETUP.md)**.

> **Do §3 before you rely on any rule.** Fill in the Compliance Status table at the top of
> `AGENTS.md`, marking each section Enforced, Partial, or Not met. It is fifteen minutes and it is
> what keeps the whole document trustworthy — an agent that cites a rule, follows it to a file that
> does not exist, and wastes a session will discount every other rule in the file afterwards.

---

## What is deliberately excluded

**No application source.** No `src/`, no schema, no migrations, no `package.json`, no lockfile,
no `Dockerfile`. This is configuration, not a starter project.

**No secrets, and none required.** Every credential in `.mcp.json` is an environment-variable
reference.

**No `.agents/skills/` mirror.** Design skills have nothing to do in a repository with no
interface, so the directory is absent rather than empty.

`.agent/workflows/` **is** included — a command mirror for a second tool that reads from that path.
In a backend repository this is frequently dead weight: a dozen files kept in sync for a reader who
does not exist. Deleting it is a legitimate choice, covered in `SETUP.md` §6. Decide knowingly
rather than inheriting it.

---

## Requirements

Nothing is mandatory. Every piece degrades to "delete this file" rather than breaking the rest.

| For | You need |
| :-- | :-- |
| Hooks, commands, the subagent | An agent runtime that reads `.claude/` and `AGENTS.md` |
| The quality gate | GitHub Actions, plus package scripts named in `SETUP.md` §5 |
| Spec drift check | A committed API spec and a script that regenerates it |
| Migration guard | A migrations directory — adjust the path pattern to match yours |
| MCP servers | The env vars named in `.mcp.json`; delete the servers you do not use |

---

## Adapting it to your stack

The rules are written against a concrete stack — Hono, Drizzle, PostgreSQL — deliberately. A rule
genericised into `{{ORM}}` is unusable until filled in, and most people never fill it in.

- `.claude/rules/common/` transfers unchanged to any language.
- `.claude/rules/backend/` is the layer to replace wholesale for a different ORM or HTTP framework.
- `AGENTS.md` sections map onto those tiers; delete a section with its tier.
- **Never renumber rules if several repositories share the numbering.** A review citing "Rule 12"
  otherwise means two different things depending on who is reading. Only append.

---

## Design decisions worth knowing before you edit

Full detail in **[docs/RATIONALE.md](docs/RATIONALE.md)** — 14 entries, each one something that
cost someone real time. The four that catch people most often:

**Comma-separated globs stay in one string.** A YAML list looks tidier and stops the rule matching
any file — with no error, no warning, and nothing in the logs.

**`--check` mode exists because write mode cannot replace it.** A write-mode sync run overwrites
staleness before it can observe it. Wire `--check` into CI; wire the write mode into nothing.

**The strip pipeline verifies both directions.** Checking only that production lost the files
misses the failure where the development branch lost them too. And it merges rather than rebases on
the way back — rebasing rewrites the strip commit and the branches diverge permanently.

**Ignore flags on a dependency audit are usually the wrong fix.** Check where the advisories come
from first; they frequently all arrive through one parent. Force the transitive dependency to a
patched release via `overrides`, then delete the flags. A flag left behind after the problem is
fixed will hide the next report for a different vulnerability.

---

## FAQ

**Will cloning this run any GitHub Actions?**
No. Every workflow triggers on `dev` or `prod`, and this repo has only `main`. Nothing runs on push
and no secrets are needed. They activate when you create those branches in your own repo.

**Do I have to adopt all of it?**
No. `SETUP.md` §1–§5 is the useful minimum: placeholders, the compliance table, hooks, and the
gate. The strip pipeline is optional and comes last because it is the only part that deletes files.

**Why is `AGENTS.md` so much longer than the frontend one?**
Because security and data-access rules have to be spelled out, and backend architecture is uniform
enough that the contract can be brief. See [How a backend layer differs](#how-a-backend-layer-differs-from-a-frontend-one).

**What is the Compliance Status table for?**
Most repositories adopt rules after growing a real domain, so some rules describe the present and
others describe a target. The table states which is which. It is the highest-value section in
`AGENTS.md` and the one most often skipped.

**Is this specific to one agent runtime?**
The rules, gate, and scripts are portable. The hook wiring in `.claude/settings.json` and the
`.mcp.json` format target Claude Code.

---

## License

MIT License. See [LICENSE](LICENSE).
