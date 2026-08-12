# Setup

Ordered by dependency, not by importance. Each step is verifiable before the next one starts, and
the step that can destroy files comes last on purpose.

Budget about an hour. Steps 1–6 are the useful minimum; 7–8 are opt-in.

> **Read this first: the workflows arrive disarmed.**
>
> Every workflow in `.github/workflows/` triggers on `dev` or `prod` only. This repo ships with
> just `main`, so nothing runs, and no secrets are needed. They activate when you create those two
> branches in your own repo — deliberately, because a quality gate has nothing to guard until there
> is a branch to promote into.

---

## 1. Copy the layer in

Copy everything except this file, `README.md`, and `docs/RATIONALE.md`:

```bash
CFG=/path/to/be-agent-config
cp -R "$CFG"/{.claude,.agent,_workflow-source,.github,scripts} .
cp "$CFG"/{CLAUDE.md,AGENTS.md,SSOT.md,.mcp.json} .
```

Then **read `.gitignore`.** `.claude/settings.local.json` and any `.env*` must be ignored before
your first commit, not after.

---

## 2. Fill in every placeholder

```bash
grep -rn '<[a-zA-Z][a-zA-Z -]*>' CLAUDE.md AGENTS.md SSOT.md .mcp.json .claude/
```

| File | What to replace |
| --- | --- |
| `CLAUDE.md` | Project name, stack summary, dev port, docs and spec paths |
| `AGENTS.md` | **The Compliance Status table — see §3, do this before anything else** |
| `SSOT.md` §What, §Ecosystem | Scaffolding; replace wholesale |
| `SSOT.md` §Stack onward | Module structure, layer rules, env vars — edit in place |
| `.mcp.json` | Environment-variable names for tokens; delete servers you do not use |

Three optional shared docs ship as `.claude/*.example.md`. Fill one in, rename it to drop
`.example`, and uncomment its import line at the bottom of `CLAUDE.md`. **Delete the ones you do
not need.**

`DATABASE.example.md` deserves a real read rather than a skim. It is the only place recording
which production database operations are permitted, and on a backend repo that distinction is the
difference between a debugging session and a data-loss incident.

---

## 3. Fill in the Compliance Status table — before you use the rules

Most repos adopt rules **after** growing a real domain, so some sections will describe what the
code already does and others a target it has not reached.

Say which is which, in the table at the top of `AGENTS.md`. This is the highest-value fifteen
minutes in this setup, and the step most often skipped.

The failure it prevents is specific: an agent cites a rule, follows it to a file that does not
exist, wastes a session — and from then on treats every rule in the document as unreliable. One
inaccurate row costs you the whole file's authority.

Three conventions that make the table work:

- **Three states, not two.** "Partial" carries most of the value.
- **Say what to do in the meantime.** A section marked Not met should name the shape to follow
  until the migration lands, or each contributor invents a third one.
- **Record deliberate oddities.** A health endpoint reporting a failed dependency inside a 200
  response is the kind of thing someone "fixes" without knowing it was intentional.

---

## 4. Agent tooling — MCP servers, wrappers, plugins

This is what the agent actually reaches for on every task. Hooks stop bad edits; **this decides how
well it works in the first place**, so it is worth ten minutes even though nothing breaks if you
skip it.

### Every tool by name, and where it is covered

Search this table first — several tools below are discussed under generic headings, so their names
only appear in prose.

| Tool | What it is | Ships here? | Covered in |
| :-- | :-- | :-- | :-- |
| **Serena** | Semantic code search and edit over a language server | `.mcp.json` | [below](#serena--install-it-or-delete-the-rules-that-assume-it) |
| **Context7** | Live library documentation lookup | `.mcp.json` | server table below |
| **GitHub MCP** | Pull requests, issues, and reviews inside a session | `.mcp.json` | server table below |
| **Postgres MCP** | Database schema, health, and query plans (`db-dev`, `db-prod`) | `.mcp.json` | server table below · `DATABASE.example.md` |
| **Dokploy · Cloudflare · Hostinger** | Deployment, DNS, and VPS control | `.mcp.json` | server table below — delete if not your vendors |
| **RTK** | Token-reducing shell proxy | **No** — machine-local | [Command wrappers](#command-wrappers--rtk-or-your-own) |
| **Ponytail** | Context-trimming plugin | **No** — machine-local | [Plugins](#plugins--ponytail-or-your-own) |
| **DeepSeek Code Review** | AI review comment on pull requests | `.github/workflows/` | [below](#ai-code-review-on-pull-requests--deepseek) · README § GitHub configuration |

**react-doctor** and **impeccable** are frontend tools and are deliberately absent — a repository
with no interface has nothing for either to check. They ship with the frontend and docs-site layers.

### The servers in `.mcp.json`

Eleven ship. **Most projects should delete most of them.** Every connected server spends context on
its tool definitions before you have asked anything, so an unused server is a permanent tax.

| Server | What it gives the agent | Needs | Keep it if |
| :-- | :-- | :-- | :-- |
| `serena` | Semantic code search and edit over a language server — find a symbol, its references, its implementations, rename it safely | `uvx` ([Astral uv](https://github.com/astral-sh/uv)). No token | **Almost always.** See below |
| `context7` | Current library documentation, fetched live | `npx`. No token | You use libraries that moved recently |
| `github` | Pull requests, issues, reviews, and branches from inside a session | `GITHUB_PERSONAL_ACCESS_TOKEN` | You want the agent to open and read pull requests |
| `db-dev` · `db-prod` | Query and inspect a database — schema, health, index advice, query plans | `DB_DEV_URI` / `DB_PROD_URI`, plus a tunnel if the port is not public | **Very likely** — this is a backend. Read `DATABASE.example.md` first |
| `dokploy-mcp` | Deployment platform control — applications, deploys, logs, backups | `DOKPLOY_URL`, `DOKPLOY_API_KEY` | You deploy with Dokploy. Otherwise **delete** |
| `cloudflare` | DNS, Workers, and account resources | OAuth in an interactive session | You use Cloudflare. Otherwise **delete** |
| `hostinger-hosting` · `-domains` · `-dns` · `-vps` | VPS, domain, and DNS management | `HOSTINGER_API_TOKEN` | You host with Hostinger. Otherwise **delete all four** |

Deleting a server is just removing its object from `.mcp.json`. Nothing else references them.

> **The four infrastructure servers are vendor-specific and are the first things to cut.** They are
> in here because the project this was extracted from uses those vendors, not because the layer
> needs them. Replace them with your own provider's server, or run with none — the gate, the hooks,
> and the rules do not care.

### Serena — install it, or delete the rules that assume it

`CLAUDE.md` § Tool Priority contains a **strict enforcement block**: always use Serena for code
files, never use the built-in file readers for them. That block is the single largest behavioural
instruction in the file.

**If Serena is not installed, that instruction is telling your agent not to read your code.** The
block does have a documented fallback — report the failure, log it, then use built-in tools — so it
degrades rather than deadlocks. But you get a warning on every task and a confused agent.

So pick one, deliberately:

```bash
# Install uv, which provides uvx. The server itself needs no separate install —
# the .mcp.json entry fetches it on first run.
curl -LsSf https://astral.sh/uv/install.sh | sh
```

**Or** delete the § Tool Priority section from `CLAUDE.md` and the `serena` entry from `.mcp.json`,
together. Deleting one without the other is the failure case.

Two details in the shipped configuration worth knowing:

**`ENABLE_TOOL_SEARCH: "true"`** defers Serena's tool definitions until they are needed. It cuts the
per-session cost substantially. The trade-off: Serena's own instructions are deferred too, so the
session must call `initial_instructions` once before its first symbol search — which is exactly what
`CLAUDE.md` § Session Start already mandates.

**The `alwaysAllow` list** pre-approves Serena's read and edit tools so you are not answering a
permission prompt every few seconds. Read it before adopting it: it includes symbol editing and
deletion. Trim it if that is more trust than you want to extend by default.

### If you work across several repositories at once

`.claude/SERENA-WORKSPACE.example.md` covers running one Serena project spanning several repos, so
symbol search reaches all of them. It is genuinely useful on a multi-repo product and pure overhead
on a single repo.

Fill it in only if you need it; otherwise delete the file. Two things it will save you: the
umbrella is machine-local configuration that a fresh clone does not inherit, and path prefixes
resolve against the umbrella root rather than your repo — which fails loudly, but only if you know
to expect it.

### Command wrappers — RTK, or your own

If you route shell commands through a wrapper — a token-reducing proxy such as **RTK**, a sandbox,
an audit recorder — declare it in `CLAUDE.md` § Command Wrapper **as a hard rule**, and prefix every
command in that file with it.

The reference project uses one, and it was stripped from this layer on purpose: it is machine-local
tooling that a fresh clone will not have, and a rule pointing at a missing binary fails every
command. The **shape** is left in place so you can slot yours in.

Why it has to be a hard rule rather than a note: a wrapper mentioned in passing gets dropped the
moment a task gets busy, and then half your commands are wrapped and half are not — which is worse
than never wrapping at all, because the numbers stop meaning anything.

### Plugins — Ponytail, or your own

`.claude/settings.json` ships with **no plugins enabled**, and that is deliberate rather than an
oversight.

The reference project runs one — **Ponytail**, which trims context — configured through
`enabledPlugins` plus a couple of environment variables. It was removed here for the same reason as
the command wrapper: a plugin declared but not installed is a startup error for everyone who clones
this.

If you use plugins, they go in the same file:

```jsonc
{
  "enabledPlugins": { "<plugin>@<source>": true },
  "env": { "<PLUGIN_SETTING>": "<value>" }
}
```

Keep them out of `.claude/settings.local.json` if the whole team should get them, and in it if the
choice is yours alone. The `.gitignore` here already excludes the local file.

### AI code review on pull requests — DeepSeek

`.github/workflows/deepseek-review.yml` posts an AI review comment on pull requests into `dev`,
using [`hustcer/deepseek-review`](https://github.com/hustcer/deepseek-review) — which accepts any
OpenAI-compatible endpoint, so the provider is your choice despite the name.

Add a `DEEPSEEK_CODE_REVIEW_TOKEN` secret and it runs. Details in
**README § GitHub repository configuration**.

The prompt is written against **this** layer, not a frontend one. It reviews against `AGENTS.md`
§B layer boundaries, §C the error envelope, §D database rules, §F security, §G code quality, §H
query performance, and §I runtime hardening — and it excludes generated migrations and the exported
spec, which `AGENTS.md` forbids hand-editing anyway.

Three things in it worth keeping if you edit it:

**Never add `actions/checkout`.** The workflow runs under `pull_request_target`, which puts your
repository secrets in scope so it can comment on fork pull requests. Checking out and executing the
pull request's code under that trigger hands your secrets to anyone who opens one. On a backend
those secrets sit closer to production than on a frontend. The action reads the diff over the API
instead.

**`dev` only, and no `synchronize`.** A `dev → prod` diff re-adds the entire AI config the strip
pipeline removed and exceeds the provider's diff limit. And without `synchronize`, a push does not
stack another review — re-run on demand by commenting `/ask-deepseek`.

**Do not tell it to skip your security checks unless they actually run on `dev`.** If your quality
gate only runs on promotion to `prod` while a lighter workflow covers `dev`, then the audit and
secret scan have *not* run when this review fires. The shipped prompt says so explicitly, and it is
the difference between a useful review and one that stays quiet about the things that matter.

---

## 5. Wire the hooks

```bash
chmod +x .claude/hooks/*.sh
```

**The distinction that matters:** `PreToolUse` hooks can **block** — `exit 1` stops the tool call
before it happens. `PostToolUse` hooks are advisory; a non-zero exit is reported and ignored. So
anything that must not happen belongs in `PreToolUse`.

### The migration guard is the important one

A migration that has already run must never be edited. Change it and the migration history differs
between environments — damage that surfaces only when the next environment deploys.

```bash
if [[ "$FILE" =~ (^|/)(migrations|drizzle)/.*\.(sql|ts)$ ]]; then
  echo "[migration-guard] BLOCKED: $FILE is a migration. Create a new one instead." >&2
  exit 1
fi
```

The fix it forces is always the same and always safe: **create a new migration.**

**Match the path pattern to your actual directory layout, then test it by triggering it.** Ask the
agent to edit a migration and confirm it is refused. A guard whose pattern does not match never
fires and never complains — reading the script cannot tell you that.

---

## 6. Make the gate runnable

`.github/scripts/quality-gate.sh` calls package scripts, so those must exist:

```jsonc
{
  "scripts": {
    "fl:ci": "<format check> && <lint>",
    "type-check": "tsc --noEmit",
    "build": "<production build>",
    "spec:export": "<regenerate the committed API spec>",
    "db:generate": "<generate migrations from schema>"
  }
}
```

Four steps here have no frontend equivalent:

| Step | What it catches |
| --- | --- |
| **API spec drift** | Regenerates the spec and fails if the committed file changed — someone altered a route without updating the contract |
| **Migration drift** | Schema and migrations have diverged |
| **Index coverage** | A frequently filtered column has no index. Usually advisory — a missing index is not always a bug, but is always worth seeing |
| **Runtime hardening** | Timeouts, pool limits, and similar production settings are present |

**Spec drift is the one to wire first if you wire only one.** The committed spec is your only
cross-repo contract, and consumers generate their clients from it. Without this check the contract
degrades quietly, and the cost lands in someone else's repo.

> **Name collision to watch for.** "Index coverage" here means **database indexes**. Elsewhere in
> this config, "index coverage" means `INDEX.md` files listing commands and rules. Both checks can
> run in the same gate.

Run it locally before opening any pull request:

```bash
bash .github/scripts/quality-gate.sh origin/dev
```

### On dependency audits

If you inherit an audit command wrapped in ignore flags, **check where the advisories come from
before accepting it.** They frequently all arrive through a single parent dependency, in which case
two things genuinely fix it:

1. Upgrade the parent. If that is a breaking major, do it as its own change — not folded into a CI
   change.
2. Force the transitive dependency to a patched release via `overrides`.

The second is usually enough, and then **the ignore flags can be deleted entirely.** Upgrading a
transitive dependency sometimes pulls in a new one that is also flagged; upgrade that too and run
the full gate before concluding you are done.

An ignore flag left behind after the problem is fixed is not untidiness. It will hide the next
report for a completely different vulnerability.

---

## 7. Slash commands and their mirrors — optional

```bash
bash scripts/sync-workflows.sh           # write the mirrors
bash scripts/sync-workflows.sh --check   # verify without writing — this is the CI mode
```

`--check` is the mode that catches drift, and the reason is worth internalising: a write-mode run
**overwrites staleness before it can observe it**. Wire `--check` into your gate; wire the write
mode into nothing.

`.agent/workflows/` exists for a second tool that reads commands from that path. In a backend repo
this is frequently **dead weight** — a dozen files kept in sync for a reader who does not exist.

| Choice | Consequence |
| --- | --- |
| Keep it | Cheap and automatic; ready if a second tool is ever used |
| Delete it | Cleaner, but must be restored if the habit changes |

Neither is wrong. What is wrong is **not knowing which applies**, because until then nobody can
judge whether running a drift check over it is worth anything.

---

## 8. The AI-config strip pipeline — last, and only if you want it

**This is the only part that deletes files. Everything else should be working before you touch it.**

| Script | Role |
| --- | --- |
| `strip-paths.sh` | **The single source of truth** for what gets removed. The other three source it |
| `strip-ai.sh` | Removes those paths on the production branch |
| `verify-strip.sh` | Asserts they are gone from `prod` **and still present on `dev`** |
| `back-merge-prod.sh` | Merges `prod` back into `dev` so the branches do not diverge |

Three things that are not obvious, each of which has already cost someone a debugging session:

**One list, sourced — never copied.** When `STRIP_PATHS` was duplicated across scripts, updating
one and not the others made the strip half-land: production kept part of the config and nothing
reported an error.

**Verify both directions.** Checking only that `prod` lost the files misses the failure where `dev`
lost them too. Only the second assertion catches that.

**Merge, never rebase, on the way back.** Rebasing rewrites the strip commit and the branches
diverge permanently.

Adopt it in this order:

1. Run `strip-ai.sh` on a throwaway branch and inspect what disappeared.
2. Run `verify-strip.sh` and confirm it fails when you deliberately skip a path.
3. Only then wire it into `strip-ai-on-pr.yml`.

---

## Verify the whole thing

```bash
grep -rn '<[a-zA-Z][a-zA-Z -]*>' CLAUDE.md AGENTS.md SSOT.md   # nothing unfilled
bash .github/scripts/check-comment-blocks.sh                   # exits 0
bash scripts/sync-workflows.sh --check                         # mirrors in sync
bash .github/scripts/quality-gate.sh origin/dev                # the real gate
```

Then the test no script performs: open a session and ask the agent to edit an existing migration.
If it does, the migration guard is prose rather than a guardrail — check its path pattern against
your layout, and treat that as the general remedy whenever a rule is not holding.
