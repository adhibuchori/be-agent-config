# Setup

Ordered by dependency, not by importance. Each step can be checked before the next one starts, and
the step that can delete files comes last on purpose.

Budget about an hour. Steps 0–6 make the layer work on your machine, 7–8 wire the commands and
GitHub, and 9 is opt-in.

> **Read this first: the workflows arrive disarmed.**
>
> Every workflow in `.github/workflows/` starts only from a pull-request event: nothing runs on a
> push, a schedule or a clone, and no bot opens update pull requests (§8 says why). The gate,
> deploy, strip and review workflows also wait for pull requests into `dev` or `prod`, which this
> repo does not have, so they activate when you create those branches in your own repo. The three
> read-only checks (`workflows-lint`, `dependency-review`, `codeql`) run on any pull request; on a
> private repository the last two skip themselves until `CODE_SECURITY` is set (README § GitHub
> repository configuration).

---

## 0. Tools you need

| Tool              | Needed for                                                                              | Without it                                                                      |
| :---------------- | :-------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------ |
| Claude Code       | The hooks, commands and subagent in `.claude/`                                          | The layer is only documents                                                     |
| bash 3.2+ and git | Every hook and script (macOS's `/bin/bash` is enough)                                   | Nothing runs                                                                    |
| python3 3.8+      | The command analyzer, `db-guard.sh`, the unlock and `.env` helpers, `ai-config.sh`      | The guards refuse, or fall back to a few plain-text rules; `ai-config.sh` fails |
| jq                | Faster payload reads in the hooks                                                       | Optional: python3 reads them                                                    |
| Bun               | The package scripts, the tests and both gate runners                                    | The gates cannot run                                                            |
| Node.js 20+       | The `.mjs` checks: folder shape, coverage policy, coverage files                        | Those gates fail                                                                |
| gitleaks          | The staged secret scan before each commit                                               | That pre-commit gate fails                                                      |
| uv                | Installing the pinned SkillSpector that `scripts/check/skills.sh` runs                  | The skill scan fails and prints the install command                             |
| gh, signed in     | `scripts/ops/pr-ready.sh`, which `/merge-pr` and `/promote` run                         | Those commands cannot read a pull request                                       |
| bubblewrap, socat | Claude Code's Bash sandbox on Linux and WSL2 (macOS needs nothing; not WSL1 or Windows) | Claude Code warns and runs commands unsandboxed; the hooks still apply          |

No hook downloads anything. The pull-request gate installs what it runs: the lockfile's packages,
one pinned gitleaks build verified by checksum on a Linux runner, and the pinned SkillSpector
through uv when a command, agent or hook changed.

---

## 1. Copy the layer in

Copy the layer, not this repository's own documents (`README.md`, this file, `docs/RATIONALE.md`,
`docs/assets/`, `LICENSE`, `.markdownlint-cli2.jsonc`):

```bash
CFG=/path/to/be-agent-config
cp -R "$CFG"/{.claude,.agent,_workflow-source,.github,.husky,scripts} .
cp "$CFG"/{CLAUDE.md,AGENTS.md,SSOT.md,.mcp.json,.skillspector-baseline.yaml} .
cp "$CFG"/{bunfig.toml,knip.ts,.oxfmtrc.json,.oxlintrc.json,.oxlintignore,.gitleaks.toml,.dockerignore} .
mkdir -p docs && cp "$CFG"/docs/unlock.md docs/   # the hooks' refusals link to it
```

The tool configs overwrite yours of the same name: merge by hand where you already have one.

Then **merge `.gitignore`.** `.claude/settings.local.json`, `.claude/state/`, `.skillspector/`
and every real `.env*` file must be ignored before your first commit, not after; the `.env.example`
and `.env.<target>.example` templates stay committed.

---

## 2. Fill in every placeholder

Placeholders are named, never blank, so one search finds them:

```bash
grep -rn --exclude-dir=hooks --exclude-dir=anti-patterns --exclude-dir=commands \
  --exclude=agent-config.example.json '<[a-zA-Z][a-zA-Z -]*>' \
  CLAUDE.md AGENTS.md SSOT.md .mcp.json .claude/ _workflow-source/ .github/PULL_REQUEST_TEMPLATE/
```

It skips the anti-patterns, whose angle brackets are examples, and the generated command mirror.
It still prints command syntax (`<file>`, `<paths>`, `<sha>`), TypeScript generics in the code
samples (`Promise<HealthResponse>`) and the pull-request template's `<details>` and `<summary>`
tags; leave those. Two placeholders sit outside that search, in `.github/`: `@your-github-handle`
in `CODEOWNERS`, and the `<...>` repository description in the review workflow's `sys-prompt`
([§4](#ai-code-review-on-pull-requests-deepseek)).

| File                                         | What to replace                                                                                                                                                                                                                                                              |
| :------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `CLAUDE.md`                                  | Project name, stack summary, dev port, docs and spec paths                                                                                                                                                                                                                   |
| `AGENTS.md`                                  | **The Compliance Status table: see §3, do it before anything else**                                                                                                                                                                                                          |
| `SSOT.md` § What, § Ecosystem                | Scaffolding; replace wholesale                                                                                                                                                                                                                                               |
| `SSOT.md` § Stack onward                     | Architecture, auth, error contract, database, tests, pipeline, env vars; edit in place                                                                                                                                                                                       |
| `.mcp.json`                                  | Delete the servers you do not use (§4)                                                                                                                                                                                                                                       |
| `_workflow-source/promote*.md`               | The deploy table (`<deploy platform>`, `<app-name>`, `<app-id>`, `<app-host>`) and the `<read-env command>` of your platform. Edit here, then run `bash scripts/sync/workflows.sh`                                                                                           |
| `<reference-module>`                         | The module every new one is copied from (`CLAUDE.md`, `AGENTS.md`, `SSOT.md`, `.claude/rules/common/patterns.md`). Name your own; with none yet, build it first to the full shape in `AGENTS.md` "How to Add a New Module". The code samples there are a health-check module |
| `.github/PULL_REQUEST_TEMPLATE/promotion.md` | `<frontend-repo>`: the repository that generates its API client from your `openapi.json`. With no such consumer, delete the Downstream section                                                                                                                               |
| `.claude/*.example.md`                       | Only the ones you keep (below)                                                                                                                                                                                                                                               |

Five shared docs ship as `.claude/*.example.md`: `OPERATIONS`, `DATABASE`, `CI-RUNNERS`,
`ANALYTICS` and `SERENA-WORKSPACE`. Copy one to its name without `.example` and fill it in; its row
in `CLAUDE.md` § On-demand References already points at the filled name, and nothing imports it,
so it costs no context until a task reads it. **Delete the ones you do not need, with their
rows.** `DATABASE.example.md` deserves a real read: it is the one place that records which
production database operations are allowed.

**Commit one `.env.<target>.example` per environment** (`.env.development.example`,
`.env.production.example`): every key the app reads, placeholder values only. `/promote` audits the
live production configuration against `.env.production.example` and cannot run that audit without
it, and `scripts/env/show.sh` reports the keys a real file is missing compared with its template.
The templates stay readable to every command; the real files do not (§5).

---

## 3. Fill in the Compliance Status table, before you use the rules

Most repos adopt rules **after** growing a real domain, so some sections describe what the code
already does and others a target it has not reached. Say which is which, in the table at the top of
`AGENTS.md`. This is the most valuable fifteen minutes in this setup, and the step most often
skipped.

The failure it prevents is specific: an agent cites a rule, follows it to a file that does not
exist, wastes a session, and from then on treats every rule in the document as unreliable. One
inaccurate row costs the whole file its authority.

- **Three states, not two.** "Partial" carries most of the value.
- **Say what to do in the meantime.** A section marked Not met names the shape to follow until the
  migration lands, or each contributor invents a third one.
- **Record deliberate oddities.** A health endpoint that reports a failed dependency inside a 200
  response is the kind of thing someone "fixes" without knowing it was intentional.

---

## 4. Agent tooling: MCP servers, wrappers, plugins

This decides how well the agent works in the first place. Nothing breaks if you skip it, but it is
worth ten minutes.

### Every tool by name

| Tool                               | What it is                                           | Ships here?                                             | Covered in                                                          |
| :--------------------------------- | :--------------------------------------------------- | :------------------------------------------------------ | :------------------------------------------------------------------ |
| **Serena**                         | Semantic code search and edit over a language server | `.mcp.json`                                             | [below](#serena-install-it-or-delete-the-rules-that-assume-it)      |
| **Context7**                       | Live library documentation lookup                    | `.mcp.json`                                             | server table below                                                  |
| **GitHub MCP**                     | Pull requests, issues and reviews inside a session   | `.mcp.json`                                             | server table below                                                  |
| **Postgres MCP**                   | Schema, health and query plans (`db-dev`, `db-prod`) | `.mcp.json`                                             | server table below · `DATABASE.example.md`                          |
| **Cloudflare**                     | DNS, Workers and account resources                   | `.claude/mcp/cloudflare.example.json`, loaded on demand | [On-demand servers](#on-demand-servers)                             |
| **Deploy platform · VPS provider** | Deployment and VPS control                           | `.claude/mcp/*.example.json`, loaded on demand          | [On-demand servers](#on-demand-servers)                             |
| **Command wrapper**                | Output filter, sandbox or audit recorder             | **No**, machine-local                                   | [Command wrappers](#command-wrappers)                               |
| **Plugins**                        | Session add-ons                                      | **No**, machine-local                                   | [Plugins](#plugins)                                                 |
| **DeepSeek Code Review**           | AI review comment on pull requests                   | `.github/workflows/`                                    | [below](#ai-code-review-on-pull-requests-deepseek) · README § CI/CD |

**react-doctor** and **impeccable** are frontend tools and are deliberately absent: a repository with
no interface has nothing for either to check.

### The servers in `.mcp.json`

Five ship, each pinned to an exact release. **Most projects should delete some of them.** Every
connected server spends context on its tool definitions before you ask anything, so an unused
server is a permanent tax.

| Server               | What it gives the agent                                                                         | Needs                                                             | Keep it if                                                           |
| :------------------- | :---------------------------------------------------------------------------------------------- | :---------------------------------------------------------------- | :------------------------------------------------------------------- |
| `serena`             | Find a symbol, its references and implementations; rename it safely                             | `uvx` ([Astral uv](https://github.com/astral-sh/uv)). No token    | **Almost always.** See below                                         |
| `context7`           | Current library documentation, fetched live                                                     | `npx`. No token                                                   | You use libraries that moved recently                                |
| `github`             | Pull requests, issues, reviews and branches from inside a session (hosted server)               | `GITHUB_PERSONAL_ACCESS_TOKEN`                                    | You want the agent to open and read pull requests                    |
| `db-dev` · `db-prod` | Schema, health, index advice and query plans. Both start read-only (`--access-mode=restricted`) | `DB_DEV_URI` / `DB_PROD_URI`, plus a tunnel if the port is closed | **Very likely**: this is a backend. Read `DATABASE.example.md` first |

Deleting a server is removing its object from `.mcp.json`. The `.claude/settings.json` entries that
name `db-prod` or `github` then match nothing, which is harmless. `bash scripts/check/ai-config.sh`
fails on any `npx`, `bunx` or `uvx` server that is not pinned to a version.

**Permissions for MCP tools live in `.claude/settings.json`, never in `.mcp.json`.** Claude Code
reads no permission field there, so an `alwaysAllow` list in `.mcp.json` does nothing. The shipped
settings ask before every `mcp__db-prod__execute_sql` call, and `db-guard.sh` holds anything but
one read-only statement until you unlock `db` (§5). Because `bypassPermissions` mode skips `ask`
rules, and a text check can misread SQL, `db-prod` also runs read-only: that server mode is what
actually holds production. Drop the flag only if you want the agent able to fix production data
during an incident.

### On-demand servers

A server you reach for once a month should not cost context in every session. Three examples ship
in `.claude/mcp/`, outside `.mcp.json`: `deploy-platform.example.json` (deployments, logs),
`vps-provider.example.json` (VPS, domains, DNS) and `cloudflare.example.json` (DNS, Workers and
account resources, as Cloudflare's hosted server). To use one:

1. Copy it to `.claude/mcp/<name>.json` and fill in your provider's MCP package, pinned to the exact
   version you checked, and its host. Rename the env keys to the ones that package reads, and keep
   the `${VARIABLE}` values that point at your shell. `ai-config.sh` checks the pin of the copy;
   the `.example.json` placeholder fails that check until you replace it.
2. Load it for one session: `claude --mcp-config .claude/mcp/<name>.json`.

`cloudflare.example.json` has nothing to pin or rename: copy it and set `CLOUDFLARE_API_TOKEN` in
your shell. If your deployment platform's server can redact environment values in its output, turn
that on: a tool result lands in the transcript. Delete the files you do not use.

### Serena: install it, or delete the rules that assume it

`CLAUDE.md` § Agent Tooling sends the agent to Serena's symbol tools before it reads whole files.
If Serena is not installed, that line points at tools that are not there, and the agent spends a
call finding that out on every task. So pick one, deliberately:

- **Install [uv](https://docs.astral.sh/uv/getting-started/installation/)**, which provides `uvx`.
  The `.mcp.json` entry fetches the pinned server on first run.
- **Or delete** the Serena line from `CLAUDE.md` § Agent Tooling and the `serena` entry from
  `.mcp.json`, together. Deleting one without the other is the failure case.

Two details in the shipped entry:

- **`ENABLE_TOOL_SEARCH: "true"`** defers Serena's tool definitions until they are needed, which
  cuts the per-session cost. Its own instructions are deferred too, so the session calls
  `initial_instructions` once before its first symbol search; that is also where Serena reports
  which project is active (`.claude/SERENA-WORKSPACE.example.md`).
- **The pin** (the commit Serena's `v1.7.0` tag names; a tag can move, a commit cannot) keeps a
  new release from changing your tools mid-project. Upgrade deliberately: change the pin, restart
  the session, and confirm the handshake with `claude mcp list`. Serena's editing tools pass
  through the same write hooks as `Edit`.

`.claude/SERENA-WORKSPACE.example.md` covers one Serena project spanning several repos. It is
useful on a multi-repo product and pure overhead on a single repo; delete it if you do not need it.

### Command wrappers

If you route shell commands through a wrapper (an output filter, a sandbox, an audit
recorder), declare it in `CLAUDE.md` § Command Wrapper **as a hard rule**, prefix every command in
that file with it, and list it under `commandWrappers` in `.claude/agent-config.json` (the example
file shows the format). `safety-check.sh` peels a listed wrapper before judging the command; an
unlisted one hides the command it runs, so `<wrapper> git push origin main` would be judged as
`<wrapper>`.

None ships here: a wrapper is machine-local, and a rule pointing at a missing binary fails every
command. It has to be a hard rule rather than a note, because a wrapper mentioned in passing gets
dropped once a task gets busy, and half-wrapped commands make its numbers meaningless.

### Plugins

`.claude/settings.json` enables **no plugins**, deliberately: a plugin declared there but not
installed is a startup error for everyone who clones the repo. If the whole team should get one,
add it to that file:

```jsonc
{
  "enabledPlugins": { "<plugin>@<source>": true },
  "env": { "<PLUGIN_SETTING>": "<value>" }
}
```

If the choice is yours alone, put it in `.claude/settings.local.json`, which `.gitignore` already
excludes.

### AI code review on pull requests: DeepSeek

`.github/workflows/deepseek-review.yml` posts an AI review comment on pull requests into `dev`,
using [`hustcer/deepseek-review`](https://github.com/hustcer/deepseek-review), which accepts any
OpenAI-compatible endpoint. Add a `DEEPSEEK_CODE_REVIEW_TOKEN` secret and it runs. Replace the one
`<...>` line in its `sys-prompt` with a description of this repo first.

The prompt reviews against `AGENTS.md` §B layer boundaries, §C the error envelope, §D database
rules, §F security, §G code quality, §H query performance and §I runtime hardening, and it skips
generated migrations and the exported spec. Three things to keep if you edit it:

- **Never add `actions/checkout`, and never switch to `pull_request_target`.** The workflow runs on
  `pull_request` (a branch of this repo gets the secret; a fork's run is skipped) and on
  `issue_comment` for `/ask-deepseek`, which runs from the default branch with the secret in scope.
  That path is safe only because nothing checks out or runs the pull request's code.
- **`dev` only, and no `synchronize`.** A `dev → prod` diff re-adds the whole AI layer the strip
  removed and exceeds the provider's diff limit. Without `synchronize`, a push does not stack
  another review; comment `/ask-deepseek` to re-run it.
- **Do not tell it to skip your security checks unless they run on `dev`.** The quality gate runs
  on pull requests into `dev` here, so the prompt can say the audit and secret scan ran.

---

## 5. Wire the hooks and the unlock

`.claude/settings.json` already wires every hook. Keep the executable bits, then prove the hooks on
your own machine:

```bash
chmod +x .claude/hooks/*.sh scripts/ops/unlock.sh scripts/env/*.sh scripts/check/hook-probes.sh
bash scripts/check/hook-probes.sh   # every rule, both ways, in temp folders; about ten minutes
```

Run the `chmod` line yourself (in your terminal, or with `!`): once the hooks are wired they refuse
it from Claude, because it changes a guard script.

On macOS, `/bin/bash scripts/check/hook-probes.sh` proves the hooks under bash 3.2.

### The hook contract

What every hook here relies on, and what to keep if you write your own:

- **Input is JSON on stdin.** Claude Code sets no `CLAUDE_TOOL_INPUT_*` variable, so a hook that
  reads one reads nothing.
- **Only exit 2 blocks, and only in `PreToolUse`.** The tool call is cancelled and stderr is the
  reason Claude reads. Any other exit code, `1` included, and a crash or a timeout, lets the call
  through. So every guard exits 2, and refuses when it cannot read its input or its own config.
- **`PostToolUse` runs after the write landed.** It cannot undo anything; it reaches Claude only
  through `hookSpecificOutput.additionalContext`. Format and lint run there, in one script
  (`post-edit.sh`), so they cannot race on the same file.
- **`SessionStart` and `UserPromptSubmit` hooks end in `|| true`**: an exit 2 on a prompt erases
  what the user typed.
- **Paths are anchored.** Each hook runs as `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/<name>.sh"`
  with a timeout (10 s for the guards, 20 s for `post-commit.sh`, 60 s for `post-edit.sh`), because
  a hook starts in the session's current folder, not the repo root.
- **No network.** No hook opens a connection or installs anything.
- **No hook reads permission from the prompt.** A refused command stays refused whoever asks; the
  user runs it with `!`.
- **Wrappers and package runners are unwrapped.** `env`, `sudo`, `timeout`, `xargs` and the other
  common wrappers, and `npx`, `bunx`, `pnpx` and `npm`/`pnpm`/`yarn`/`bun` `exec`, `dlx` and `x`,
  are peeled: the command inside is judged, and a `-c` string or the words of `bun exec` and
  `yarn exec` are judged as a script.
- **What a guard cannot resolve, it refuses.** A command built at run time (`$( )` as a command or
  a file to read, `eval`, text piped into a shell, a package runner's command or script built from
  `$( )` or an unknown variable) is refused even when it names nothing protected, and so is a git
  setting that changes what git runs or loads (an alias, an include, `core.sshCommand`, a credential
  helper, a proxy, `url.*.insteadOf`), whatever its value. The reason says the user can run it with
  `!`, which runs as the user, outside the hooks and (in an ordinary session) the sandbox.

`.claude/hooks/README.md` lists what each hook refuses, what it does when python3 or jq is missing,
and how to turn one off: remove its entry from `.claude/settings.json`. To change a hook, add a
probe it must stop and one it must let through, then run the harness.

### The migration guard is the important one

A migration that has already run must never be edited: the migration history then differs between
environments, and the damage surfaces only when the next environment deploys.

`migration-guard.sh` refuses `Write`, `Edit`, `MultiEdit` and Serena's write tools on any file
under `migrationsDirs` (by default `src/db/migrations`, `drizzle` and the usual Alembic folders).
The fix it forces is always the same and always safe: **create a new migration.**

**Match the folders to your layout, then test the guard by triggering it.** A folder the repo does
not have guards nothing. If your migrations live elsewhere, copy
`.claude/agent-config.example.json` to `.claude/agent-config.json` and keep only the keys you
change. Then ask the agent to edit a migration and confirm it is refused. A guard whose folders do
not match never fires and never complains, and reading the script cannot tell you that.

### The unlock: `.env` files and production writes

The hooks refuse the agent's shell reads and writes of `.env*` files, and hold its SQL writes to
production. Only you open either one, for a few minutes, with a command the hooks refuse to run for
the agent. They refuse any command they cannot resolve, so a command they cannot read comes back to
you as a `!` command instead of running. [`docs/unlock.md`](docs/unlock.md) explains the mechanism
and what it does not stop. Two lines of setup:

1. `.claude/state/` in `.gitignore` (this repo's already has it). It holds the unlock files, the
   `.env` backups and the audit log; `scripts/env/set.sh` refuses to run until it is ignored.
2. The alias in your `package.json`, so the command is `bun unlock`:

   ```jsonc
   {
     "scripts": {
       "unlock": "bash scripts/ops/unlock.sh"
     }
   }
   ```

Then run it yourself, with `!` in front inside Claude Code:

| Package manager | Open `.env*` (20 min)           | Open DB writes (15 min)        | Status · lock everything                                             |
| :-------------- | :------------------------------ | :----------------------------- | :------------------------------------------------------------------- |
| bun             | `! bun unlock env`              | `! bun unlock db`              | `! bun unlock status` · `! bun unlock off`                           |
| npm             | `! npm run unlock env`          | `! npm run unlock db`          | `! npm run unlock status` · `! npm run unlock off`                   |
| pnpm            | `! pnpm unlock env`             | `! pnpm unlock db`             | `! pnpm unlock status` · `! pnpm unlock off`                         |
| yarn            | `! yarn unlock env`             | `! yarn unlock db`             | `! yarn unlock status` · `! yarn unlock off`                         |
| no package.json | `! ./scripts/ops/unlock.sh env` | `! ./scripts/ops/unlock.sh db` | `! ./scripts/ops/unlock.sh status` · `! ./scripts/ops/unlock.sh off` |

### The sandbox under the hooks

The hooks read command lines; a script those lines run, or a program that runs commands of its own
(`watch`, `script`, `flock`, `parallel`), is out of their sight. So `.claude/settings.json` also
turns on [Claude Code's Bash sandbox](https://code.claude.com/docs/en/sandboxing), on by default
(`sandbox.enabled: true`), which the operating system enforces on every sandboxed command and
anything it starts:

- `sandbox.filesystem.denyRead` closes every real `.env*` file (`.envrc`, `.env-*` and `.env_*`
  included, at any depth) and the backups in `.claude/state/env-backups/`; `allowRead` reopens the
  `*.example` templates.
- `sandbox.filesystem.denyWrite` closes `.claude/state/unlock/`, so no sandboxed command can write
  an unlock, and `.claude/hooks/` and `scripts/ops/unlock.sh`, so none can rewrite a guard.
- `sandbox.excludedCommands` lets only `scripts/env/show.sh` and `scripts/env/set.sh` run outside
  it, since those two must reach `.env` files.

Its limits, and how to turn it off:

- **Platforms.** macOS needs nothing; Linux and WSL2 need `bubblewrap` and `socat`. WSL1 and native
  Windows are not supported. Where the sandbox cannot start, Claude Code warns and runs commands
  without it unless `sandbox.failIfUnavailable` is `true`; the hooks apply either way.
- **The retry outside it.** Your application reads `.env` when it runs, so a command that starts it
  fails inside the sandbox and is retried outside it after Claude Code asks you. Set
  `sandbox.allowUnsandboxedCommands` to `false` to forbid every such retry.
- **Your `!` commands** run outside it, except in a background session with
  `allowUnsandboxedCommands: false` and on Linux with `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` set; there,
  run `unlock` in your own terminal.
- **Turning it off.** Set `"sandbox": {"enabled": false}` in `.claude/settings.json`, or in your own
  `.claude/settings.local.json`. The hooks keep running.

---

## 6. Make the gates runnable

Two runners share one list of checks. `bash scripts/check/gates.sh` runs
`scripts/check/gates.list` on your machine, and `.husky/pre-commit` runs it on every commit with
`--hook`, choosing the gates by what is staged. `.github/scripts/quality-gate.sh` runs the same
checks and more on every pull request. Both call package scripts, so those must exist:

```jsonc
{
  "scripts": {
    "build": "bun build ./src/index.ts --outdir ./dist --target bun",
    "test": "bun test src",
    "test:coverage": "bun test src --coverage && node scripts/check/coverage-files.mjs",
    "test:integration": "RUN_INTEGRATION_TESTS=1 bun test src",
    "format": "oxfmt src scripts",
    "format:check": "oxfmt --check src scripts",
    "lint": "oxlint --type-aware src scripts",
    "fl": "bun run format && bun run lint",
    "fl:ci": "bun run format:check && oxlint --type-aware src scripts",
    "type-check": "tsc --noEmit",
    "check:dead-code": "knip",
    "check:mocks": "bun scripts/check/module-mocks.ts",
    "check:constants": "bun scripts/check/constants.ts",
    "check:folder-shape": "node scripts/check/folder-shape.mjs",
    "check:coverage-policy": "node scripts/check/coverage-policy.mjs",
    "db:generate": "drizzle-kit generate",
    "db:migrate": "bun run src/db/client/migrate.ts",
    "spec:export": "<regenerate the committed API spec>",
    "unlock": "bash scripts/ops/unlock.sh",
    "prepare": "husky"
  }
}
```

Then install the tools behind them, pinned to the exact versions you get:
`bun add -d husky knip oxfmt oxlint oxlint-tsgolint typescript drizzle-kit`. `prepare` installs the
pre-commit hook on `bun install`. §0 lists the tools outside `package.json`.

Keep the names: `gates.list`, the quality gate, `coverage-policy.mjs` (which checks that
`test:coverage` runs `coverage-files.mjs`) and `@format` (which reads the scope of `format` and
`fl:ci`) all call these scripts by name. `gates.sh` reads the package manager from the lockfile.

Three checks start empty and refuse to pass on nothing, so fill them before your first commit of
code:

| Check             | Fill in                                                                                                                                                                                                             |
| :---------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `check:constants` | `scripts/check/constants.config.json`: one entry per shared vocabulary (roles, queue names, cache prefixes) naming its home under `src/lib/constants/`. The format is in the header of `scripts/check/constants.ts` |
| `check:mocks`     | Nothing, until a test genuinely has to replace a third-party module: then one reasoned row in `ALLOWED` in `scripts/check/module-mocks.ts`. It fails while `src/` has no test file                                  |
| `test:coverage`   | `coveragePathIgnorePatterns` in `bunfig.toml`: add each raw client file by path, with the reason above it                                                                                                           |

Four pull-request steps are specific to a backend:

| Step                  | What it catches                                                                                             |
| :-------------------- | :---------------------------------------------------------------------------------------------------------- |
| **API spec drift**    | Regenerates the spec and fails if the committed file changed or is not committed, or if the generator fails |
| **Migration drift**   | Schema and migrations have diverged                                                                         |
| **Index coverage**    | A foreign-key column with no index: Postgres indexes a primary key but not a `REFERENCES` column            |
| **Runtime hardening** | Timeouts, pool limits and similar production settings are present                                           |

**Spec drift is the one to wire first if you wire only one.** The committed spec is your only
cross-repo contract, and consumers generate their clients from it. Without this check the contract
degrades quietly, and the cost lands in someone else's repo.

Run both before opening any pull request:

```bash
bash scripts/check/gates.sh                        # the pre-commit list, every gate
bash .github/scripts/quality-gate.sh origin/dev    # the pull-request gate
```

### On dependency audits

If you inherit an audit command wrapped in ignore flags, **check where the advisories come from
before accepting it.** They often all arrive through one parent dependency, and then two things
genuinely fix it: upgrade the parent (as its own change if it is a breaking major), or force the
transitive dependency to a patched release with `overrides`. The second is usually enough, and then
**the ignore flags can be deleted.** A flag left behind after the problem is fixed hides the next
report for a different vulnerability.

---

## 7. Slash commands and their mirrors

Optional, but the commands assume the GitHub settings in §8, squash merging off above all.

```bash
bash scripts/sync/workflows.sh           # write the mirrors
bash scripts/sync/workflows.sh --check   # verify without writing; this is the gate's mode
```

Edit commands in `_workflow-source/`, never in the mirrors. `--check` is the mode that catches
drift: a write-mode run **overwrites staleness before it can observe it**. Wire `--check` into your
gate; wire the write mode into nothing.

`/merge-pr` and `/promote` read a pull request's readiness with `scripts/ops/pr-ready.sh`, which
needs a signed-in `gh`. Only a passing check counts. A skipped or neutral one, such as CodeQL and
dependency review on a private repository without `CODE_SECURITY`, blocks until you confirm it is
expected to skip; the command then passes `--allow-skipped`.

`.agent/workflows/` exists for a second tool that reads commands from that path. In a backend repo
it is often dead weight. Keep it (cheap, automatic, ready if that tool arrives) or delete it
(cleaner, restored if the habit changes); what matters is deciding, so the drift check over it
means something.

---

## 8. GitHub: pull-request-only CI

README § GitHub repository configuration walks through the branches, secrets and variables. Three
settings belong here because the commands and the CI depend on them.

### Turn off squash merging

In **Settings → General → Pull Requests**, allow merge commits only. `/merge-pr` and `/promote`
merge with `--merge`, and `/branch-cleanup` proves a branch merged by comparing it with `dev`,
which only a merge commit makes possible: a squash-merged branch always reads as ahead, so it is
kept, never deleted on a guess.

### Create `dev` and `prod`, and make `dev` the default

Nothing in `.github/workflows/` runs until pull requests into those branches exist. Pull requests
target `dev`; `prod` is a promotion target.

### Why only pull-request events, and no schedulers

Every workflow here starts from a pull-request event: `pull_request`, a merged pull request
(`types: [closed]` with a `merged` guard) for the deploy and the strip, and `issue_comment` for an
on-demand review. There is no `push:` trigger, no `schedule:` and no bot that opens update pull
requests.

- **A push adds nothing a pull request did not already check.** `dev` and `prod` change only
  through merged pull requests, whose gate ran on the merge result; a `push:` trigger would run the
  same checks again on the same code, on every runner minute you pay for.
- **A timer runs on code nobody changed.** A scheduled scan spends minutes every week and opens
  pull requests nobody asked for, and in a template it would do so in every copy. Updates are a
  decision instead: `pinact run -u --min-age 7` for the pinned actions (it skips releases younger
  than seven days) and `bun update` for packages, each in an ordinary pull request that dependency
  review and the gate then read.
- **A deploy follows a merge, not a push.** A pull request closed without merging, and a direct
  push to `prod`, deploy nothing.
- **The cost is stated, not hidden.** An advisory published after a merge surfaces at the next pull
  request that touches dependencies, or when you run `bun audit` yourself; nothing watches the
  repository between changes.

If you add a workflow, keep to the same rules; `workflows-lint.yml` runs actionlint, zizmor and
`pinact --check` on any pull request that changes `.github/`.

---

## 9. The AI-config strip pipeline: last, and only if you want it

**This is the only part that deletes files. Everything else should be working before you touch
it.**

| Script               | Role                                                                            |
| :------------------- | :------------------------------------------------------------------------------ |
| `strip-paths.sh`     | **The single source of truth** for what gets removed. The other three source it |
| `strip-ai.sh`        | Removes those paths on the production branch                                    |
| `verify-strip.sh`    | Asserts they are gone from `prod` **and still present on `dev`**                |
| `back-merge-prod.sh` | Merges `prod` back into `dev` so the branches do not diverge                    |

Three things that are not obvious:

- **One list, sourced, never copied.** With `STRIP_PATHS` duplicated across scripts, updating one
  copy and not the others makes the strip half-land: production keeps part of the config and
  nothing reports an error.
- **Verify both directions.** Checking only that `prod` lost the files misses the failure where
  `dev` lost them too.
- **Merge, never rebase, on the way back.** Rebasing rewrites the strip commit and the branches
  diverge permanently.

Adopt it in this order:

1. Run `strip-ai.sh` on a throwaway branch and inspect what disappeared.
2. Run `verify-strip.sh` and confirm it fails when you deliberately skip a path.
3. Only then rely on `strip-ai-on-pr.yml`.

---

## Verify the whole thing

```bash
grep -rn '<[a-zA-Z][a-zA-Z -]*>' CLAUDE.md AGENTS.md SSOT.md   # only the syntax and generics §2 names
bash .github/scripts/check-comment-blocks.sh                   # exits 0
bash scripts/sync/workflows.sh --check                         # mirrors in sync
bash scripts/check/ai-config.sh                                # citations, budget, hook wiring, pins
bash scripts/check/ai-config-probes.sh                         # the pin rule, proven both ways
bash scripts/check/hook-probes.sh                              # every hook rule, both ways
bash scripts/check/gates.sh                                    # the pre-commit list
bash .github/scripts/quality-gate.sh origin/dev                # the pull-request gate
```

Then the test no script performs: open a session and ask the agent to edit an existing migration.
If it does, the migration guard is prose rather than a guardrail: check `migrationsDirs` against
your layout, and treat that as the general remedy whenever a rule is not holding.
