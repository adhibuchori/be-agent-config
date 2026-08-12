# Setup

Ordered by dependency, not by importance. Each step is verifiable before the next one starts, and
the step that can destroy files comes last on purpose.

Budget about an hour. Steps 1–5 are the useful minimum; 6–7 are opt-in.

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

## 4. Wire the hooks

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

## 5. Make the gate runnable

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

## 6. Slash commands and their mirrors — optional

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

## 7. The AI-config strip pipeline — last, and only if you want it

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
