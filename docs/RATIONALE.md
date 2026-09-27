# Rationale

Why the odd-looking parts of this configuration are shaped the way they are.

Several entries below look like clutter and are load bearing. This file exists so you can tell
which is which before you tidy anything.

**One rule while reading: if a pattern here looks needlessly complicated, do not simplify it.**
Each one is followed by what breaks when you do.

---

## 1. Rules load by path

Every rule under `.claude/rules/` except `common/working-agreements.md` opens with a `paths:` list:

```yaml
---
paths:
  - 'src/db/**'
  - 'src/modules/**/*.repository.ts'
---
```

Claude Code loads such a rule only once the session reads a file one of the globs matches; a rule
without `paths:` loads in every session, as `CLAUDE.md` does. Proven with a probe: a rule scoped to
`zz/**` was absent from a fresh session and present after the session read `zz/note.txt`. Generic
boilerplate (a coding-style primer, a development workflow, git and hook tutorials) was deleted
rather than scoped, and the review checklist moved to `.claude/docs/`, which nothing loads until a
command asks for it. What still loads every session has a budget (§15).

Two silent failures to know about:

- **A glob that matches nothing.** The rule never loads, and nothing says so. Check each glob
  against your layout after a folder move.
- **The wrong shape for the tool.** Claude Code reads `paths:` as a YAML list. A tool that reads a
  `globs:` key may want one comma-separated string instead, and a list there stops the rule
  matching any file, with no error. Match the shape to whichever tool reads the file.

This is the archetype for the whole file: the failure is silent, and silence reads as success.

---

## 2. `PreToolUse` blocks; everything else only complains

The single most important thing to understand about hooks.

| Event              | What exit 2 does                                                            | Any other exit code               |
| ------------------ | --------------------------------------------------------------------------- | --------------------------------- |
| `PreToolUse`       | **The tool call does not happen**, and stderr is the reason the agent reads | The call goes ahead, `1` included |
| `PostToolUse`      | Stderr reaches the agent, but the write has already landed                  | Nothing the agent sees            |
| `UserPromptSubmit` | The prompt is dropped: what the user typed is erased                        | The prompt goes ahead             |
| `SessionStart`     | Nothing it can block; stderr reaches only the user                          | The session starts                |

So a rule that must not be violated belongs in `PreToolUse` and exits 2. Put it in `PostToolUse`,
or exit 1, and you get a guard that appears installed, logs complaints, and prevents nothing. The
two prompt-side hooks here end in `|| true`, because an exit 2 there costs the user their prompt.
A crash and a hook timeout count as "any other exit code": a guard that crashes lets the call
through, which is why every guard here refuses when it cannot read its input (§16).
Claude Code also sends the tool call as JSON on stdin; a hook that reads a `CLAUDE_TOOL_INPUT_*`
variable reads nothing, because none is set.

**Corollary: test a guard by triggering it.** A guard whose path pattern does not match your
directory layout never fires and never complains. Reading the script tells you what it intends;
only triggering it tells you what it matches. `scripts/check/hook-probes.sh` does that for every
rule, both ways: what each hook must stop, and what it must let through.

---

## 3. `--check` mode, and why write mode cannot replace it

Mirror scripts run in two modes. Only one detects drift:

```bash
bash scripts/sync/workflows.sh           # write
bash scripts/sync/workflows.sh --check   # verify — this is the CI mode
```

A write-mode run **overwrites staleness before it can observe it**. Run it in CI and the mirrors
are always in sync, because the check just fixed them, so a stale or unlisted command can go
unnoticed for as long as nobody runs the check mode.

`--check` catches four distinct things; a checker that covers fewer misses the rest in silence:

1. A target file that no longer matches its source.
2. An **orphan** — a target with no source. This is the direction naive checkers forget.
3. `INDEX.md` drift, verified **both ways**: every command listed, and every listed command real.
4. Vendored third-party files, which are exempt — see §4.

---

## 4. Third-party installers leave legitimate orphans

A design or framework skill installed by its own tooling writes into `.claude/skills/`,
`.agents/skills/`, and drops a command shim into `.claude/commands/` — with **no counterpart** in
your source directory, by design. The installer owns their versioning.

A naive drift checker flags these as orphans and advises deleting them or moving them into the
source directory. Both suggestions break the next upgrade.

Hence the explicit `VENDORED` exemption list in `scripts/sync/workflows.sh`. It ships empty here:
a backend installs no design skill, so any file in a mirror without a source is a real orphan. Add
a vendored command's path to it the day you install one, and if you add a drift checker of your
own, copy that pattern before you add the checker, not after it files its first false report.

The same script reads a subfolder of `_workflow-source/` as a command namespace
(`_workflow-source/db/reset.md` is `/db:reset`) and keeps the folder in both mirrors, so a
namespaced command is neither flattened nor reported as an orphan.

---

## 5. The review workflow never uses `pull_request_target`

The AI review workflow needs a secret (the provider's token) and write access to post a comment.
`pull_request_target` offers both even to forks, by running the base branch's workflow with every
repository secret in scope, which is why it is the usual choice and why it is dangerous: a step
that checks out and runs the pull request's code hands those secrets to whoever opened it. GitHub
is moving to refuse that combination by default, and zizmor already flags it.

So the workflow runs on `pull_request`, where a branch of this repository gets the secret and a
fork's run gets none and is skipped, and on `issue_comment` for an on-demand `/ask-deepseek`, which
runs from the default branch with the secret and is filtered to owners, members and collaborators
before a runner starts. Neither path checks out the pull request: the action reads the diff over
the API. Keep that property if you edit it; it is what makes the comment path safe on a fork.

Two smaller decisions in the same workflow, both deliberate:

- **No `synchronize` in the trigger types.** The action posts no sticky comment, so every push
  would add another review.
- **Base branch only, not the promotion branch.** A `dev → prod` diff re-adds the entire AI config
  that the strip pipeline removed, and the provider rejects a diff that size.

---

## 6. The strip pipeline: one list, both directions, merge not rebase

Three rules, each against a separate failure.

**One list, sourced — never copied.** `STRIP_PATHS` lives in `strip-paths.sh`; the other three
scripts source it. With the list duplicated, updating one copy and not the others makes the strip
half-land: production keeps part of the config, and nothing reports an error.

**Verify both directions.** Asserting that `prod` lost the files misses the failure where `dev`
lost them too. Only the second assertion catches that, and it is the one people leave out.

**Merge, never rebase, on the back-merge.** Rebasing rewrites the strip commit, and the branches
diverge permanently.

One more: `git rm --cached` leaves the files present but untracked, which blocks a later rebase
for reasons that look unrelated to the strip.

---

## 7. The skip-CI marker that disarms gates silently

A skip-CI marker belongs only on a commit whose own push would retrigger the workflow that made
it. Copied onto a commit on another branch, it prevents nothing there. What it does do is disarm
the quality gate on **every** pull request whose head is that commit.

**A pull request with no checks at all is not a slow queue.** Three causes, all of which report as
"pending" rather than as a failure, so they survive indefinitely:

1. A skip-CI marker on the head commit.
2. A conflicting pull request — the provider builds a merge commit to run `pull_request`
   workflows; a conflict means no merge commit, so nothing starts.
3. A gate whose trigger omits the review branch. `branches: [prod]` alone lets everything reach the
   development branch ungated.

Check `mergeable` and the head commit's message before concluding CI is slow.

No workflow, script or command here writes the marker: nothing starts on a push, so it would have
nothing to prevent, and a copy on a pull request's head commit would silence the gate.

---

## 8. CI script divergence between repos is usually correct

The tempting conclusion, on finding several variants of a quality gate across a set of repos, is
that they have drifted and should be unified.

Check what the variance tracks first. If the gates cluster by **repo role** — APIs, web apps,
documentation sites, each with a consistent shape — that is not drift. Documentation repos
do not need the same checks as applications; a backend does not need translation-key parity.

Unifying that deletes legitimate checks. Divergence by role is the correct design; the useful thing
to hunt for is divergence **within** a role.

---

## 9. Generated clients are invisible to symbol search

If your generated API client is gitignored and your symbol-search tool respects gitignore, the
client does not exist as far as symbol search is concerned. Searches for generated hooks or types
return nothing, even though the code is on disk.

This is the one case where an empty result does not mean "absent from the scope you searched" — the
files are filtered out before the search rather than rejected by it.

Use the committed API spec instead. Turning off the gitignore filter is not the fix: it also
exposes every `.env` file to symbol search and file reads.

---

## 10. Backend-specific: the spec file is a cross-repo contract

The API spec committed at the repository root has two roles that are easy to underrate.

**It is the only cross-repo contract.** Frontend clients are generated from it. A change here is a
change every consumer sees.

**It is the only way to see the API shape from outside.** Generated clients are usually gitignored,
so symbol-search tools cannot see them (§9). The spec is committed, so the spec is what is readable.

Two consequences for the configuration:

- Regenerating the spec belongs in the workflow, not in someone's memory.
- The gate needs a **spec drift check**: run the generator, then assert the committed file did not
  change. If it did, someone altered a route without updating the contract.

```bash
step "OpenAPI Spec Drift Check"
if ! bun run spec:export; then
  echo "::error::bun run spec:export failed, so openapi.json was not regenerated"
  failed=$((failed + 1))
elif [ -n "$(git status --porcelain -- openapi.json)" ]; then
  echo "::error::openapi.json is stale or uncommitted"
  failed=$((failed + 1))
fi
```

Both branches matter. A generator that fails leaves the old file in place, so `git diff` sees
nothing; and an `openapi.json` that was never committed is invisible to `git diff` too. A check
that reads only the diff passes in both cases. Without the check the contract degrades quietly,
and the cost lands in someone else's repo.

---

## 11. Migrations are the one thing that cannot be taken back

A migration that has already run in any environment must never be edited. Change it and the
migration history differs between environments — damage that surfaces only when the next
environment deploys.

This is the strongest candidate for a `PreToolUse` guard in any backend repo, because the correct
fix is always the same and always safe: **create a new migration**.

Match the guard's path pattern to your actual directory layout, and test it by triggering it (§2).

---

## 12. Rule documents get longer as the risk gets quieter

Counter-intuitive, and worth stating so you do not "fix" it.

This backend rule document is **larger** than its frontend counterpart, while this contract
document is **smaller**. Security and data-access rules have to be spelled out: "validate input at
system boundaries" cannot be compressed into one actionable sentence; it needs the boundary list
and the failure behaviour. Meanwhile backend architecture is more uniform, so the contract states
the shape once.

The practical implication: **do not normalise document length across repos.** If your backend rule
document is as short as your frontend one, there are probably security rules that were never
written down.

---

## 13. State intentional absences explicitly

If an architectural layer does not exist yet, the contract document should say so in as many words:

```markdown
The service hook layer does not exist yet. All data fetching currently goes through the client.
This is deliberate and planned, not drift.
```

Without that sentence, the next audit reports it as a finding, and someone spends an afternoon
re-deriving that it was intentional.

**Every deliberate absence is worth one sentence in the contract.** This is the cheapest rule in
the file and the one most often skipped.

---

## 14. Count file-presence claims; do not infer them

A claim of the form "file X does not exist in repo Y" must be **counted**, not assumed.

A presence claim inferred from a pattern ("backend repos have no second-tool mirror directory")
is easy to write down and easy to get wrong: the directory may exist in every repo, and the one
that really differs may have been put there by a skill installer rather than by any architectural
decision.

Auditing file presence is far cheaper than auditing intent, and it is the kind of claim that gets
repeated once written down. Run the `ls`.

---

## 15. What loads every session has a byte budget

`CLAUDE.md` plus every rule without `paths:` loads before the task does, on every task, so it is
the most expensive text in the repository. `scripts/check/ai-config.sh` holds it to 15,000 bytes in
pre-commit and in the pull-request gate. Today it is 13,114: `CLAUDE.md` at 8,836 and
`working-agreements.md` at 4,278.

- **Bytes, not lines.** A line count rewards long lines; the budget reads `wc -c`.
- **No `@` imports in `CLAUDE.md`.** An import pulls a whole file into every session. The check
  refuses one even inside an HTML comment, so a commented-out import cannot come back unnoticed.
  `CLAUDE.md` § On-demand References names each file and says when to read it instead.
- **Over budget, move text out, do not compress it.** Anything tied to a path becomes a `paths:`
  rule; anything a person reads becomes a doc; anything deterministic becomes a hook or a gate.

What fails when the budget goes: the rules that matter compete with boilerplate for the same
attention, and nobody can say which lines the agent actually weighed.

---

## 16. Guards read commands like a shell, and prove it with probes

A guard that matches substrings fails both ways. It blocks harmless commands: a commit message that
mentions `git push origin main` is not a push. And it misses real ones: `git -C . push origin
main`, `bash -c '...'`, `eval`, a push after `&&`. `safety-check.sh` reads a command the way a
shell does (quotes, heredocs, `$( )`, backticks, `bash -c`, `eval`, aliases, pipes into a shell)
and judges each command it finds. Wrappers (`env`, `sudo`, `timeout`, `xargs`, ...) and package
runners (`npx`, `bunx`, `npm`/`pnpm`/`yarn`/`bun` `exec`, `dlx` and `x`) are peeled, and the shell
text a runner takes (a `-c` string, the words of `bun exec '…'`) is read as a script. All of the
examples above behave as described; the probes prove it.

It **fails closed**. Only exit 2 blocks (§2), so a guard that crashes, or runs past its timeout,
would let the call through; instead, a payload it cannot parse, an analyzer crash or an analysis
over 8 s is refused. Without python3 only plain-text rules stand in (protected pushes, recursive
deletes, a hard reset or forced clean, a skipped gate, `.env*` names and the unlock), and Claude is
told so; everything else runs unchecked on such a machine.

**What it cannot resolve, it refuses.** A file name or command built at run time used to be the
analyzer's blind spot: `$( )` output used as a command or a file to read, `eval` and decoded
payloads, text piped into a shell, a path assembled through `IFS`, `dotglob` or an array, a package
runner whose command or script is built from `$( )` or an unknown variable, a command git runs from
a setting. Each is now refused whether or not it names a secret, and so is any git setting that
changes what git runs, loads or connects to (an alias, an include, `core.sshCommand`, a credential
helper, `protocol.*.allow`, a proxy, `url.*.insteadOf`, `safe.directory`), whatever its value. The
refusal tells Claude that the user can run it with `!`, which runs as the user, with the user's own
access, outside the hooks and (in an ordinary session) the sandbox.
Refusing some harmless commands is the price, paid on purpose; `cat $(git ls-files '*.md')` stays
open, because git confirms that file list before the hook accepts it.

`scripts/check/hook-probes.sh` proves every rule both ways, what it must stop and what it must let
through, in temporary repositories, with the fail modes (python3 missing, jq missing, a broken
payload) and a linked git worktree included. It runs in pre-commit when a commit stages a hook,
`settings.json`, the probes, `scripts/ops/unlock.sh` or `scripts/env/`, and on every pull request;
other code skips it, because it takes about three minutes. A change to a hook adds one probe it
must stop and one it must let through, and is proven load-bearing by breaking the rule and watching
the probe fail.

The limit is stated, not hidden: the hooks read command lines, not the scripts those lines run, and
a program they do not know that runs commands of its own (`watch`, `script`, `flock`, `parallel`)
is judged by name only. So the operating system's sandbox sits underneath them (§21), and
`docs/unlock.md` lists what neither stops.

---

## 17. Commands, agents and hooks are scanned like dependencies

A slash command, a subagent or a hook is text the agent follows with its own permissions. An
instruction hidden in an HTML comment, or a shell step that sends a `.env` file somewhere, is a
supply-chain risk like a compromised package, and review rarely catches it because the file reads
as documentation.

`scripts/check/skills.sh` runs SkillSpector, pinned to one commit, over `_workflow-source/`, the
command mirrors, `.claude/agents/` and `.claude/hooks/`: the staged targets in pre-commit, the
changed ones on a pull request. It runs locally (`--static`); the `--llm` mode, which sends file
text to a provider, is never used in CI.

- **Fix the text first.** Most findings are wording: an extra HTML comment, or a sentence that reads
  like an instruction to bypass something. Reword it.
- **Suppress narrowly, with a reason.** `.skillspector-baseline.yaml` holds one entry per finding
  (id, file, matched text, reason), third-party trees by hash, and files the scanner read only in
  part, by exact file and reason code. A file read only in part fails otherwise: an unread part is
  not a clean one.
- **Review every diff to the baseline by hand.** It is the list of findings this gate ignores.

---

## 18. Merge commits, never squash

`/merge-pr` and `/promote` merge with `gh pr merge --merge`, and SETUP §8 turns squash merging off.
`/branch-cleanup` deletes a branch only when GitHub reports it `0` commits ahead of `dev`, which is
exact only when merges are merge commits. A squash-merged branch always reads as ahead, so the
cleanup would either keep every branch or delete on a guess, and it is written never to guess.

A merge commit also keeps each commit with its own date and author, where a squash folds a branch
into one commit dated the merge day. `git log --first-parent` gives the one-line-per-change view
when you want it. The strip's back-merge into `dev` is a merge for the same reason (§6).

---

## 19. The deploy is a webhook, and names no vendor

`ci-cd.yml` builds nothing. When a pull request into `prod` is merged, it posts to the
`DEPLOY_WEBHOOK_URL` secret through `.github/scripts/trigger-deploy.sh`, retrying while a build
still refuses connections, and the deployment platform builds from git.

- **Every platform has a deploy hook**; not every platform wants a registry image. A build-and-push
  job assumes one deployment model and costs minutes and storage on every promotion.
- **Switching platforms is one secret.** Nothing in the workflows, scripts or commands names a
  vendor. The promotion commands keep the platform as placeholders (`<deploy platform>`,
  `<read-env command>`), and the deploy and VPS MCP examples use neutral names (`deploy-platform`,
  `vps-provider`) that you point at your provider's package.
- **A pull request closed without merging deploys nothing**, and neither does a direct push to
  `prod`: the job checks `merged` and the base branch itself.

If your platform pulls a prebuilt image, add that job yourself; the template does not assume one.

---

## 20. CI starts only from pull requests

No workflow here has a `push:` or `schedule:` trigger, and no bot opens update pull requests.
Every run is tied to a change someone proposed.

- **A push trigger re-checks what a pull request already checked.** `dev` and `prod` change only
  through merged pull requests, whose gate ran on the merge result. The deploy and the strip run on
  the merged pull request instead (`types: [closed]` with a `merged` guard).
- **A schedule runs on code nobody changed**, spends minutes every week, and opens pull requests
  nobody asked for; copied into every repository made from this template, it does all three
  everywhere. Updates are a decision: `pinact run -u --min-age 7` for the pinned actions, `bun
  update` for packages, each in an ordinary pull request that dependency review and the gate read.
- **`pull_request_target` is never used** (§5), every `uses:` is pinned to a full commit SHA, the
  top-level token is `contents: read`, and no `${{ }}` expression reaches a `run:` block.
  `workflows-lint.yml` checks those with actionlint, zizmor and `pinact --check` whenever
  `.github/` changes.

The cost is accepted on purpose: an advisory published after a merge surfaces at the next pull
request that touches dependencies, or when someone runs `bun audit`. Nothing watches the repository
between changes.

---

## 21. The unlock: opened by the user, closed by the clock

A phrase in the prompt that lifts a deny rule for one action is a permission for whoever writes
text the agent reads: anything the agent reads (a file, an issue, a web page) can contain that
phrase. No hook here reads permission from the prompt.

What it does instead:

- **Only the user opens it.** `scripts/ops/unlock.sh env|db` writes `.claude/state/unlock/<target>`
  with an expiry time. The user runs it with `!`, which does not pass through the hooks; the hooks
  refuse it from the agent in the forms the probes cover, and refuse any write, copy, link or
  delete under `.claude/state/unlock/`. A file that is expired, readable by others, a link, or
  tracked by git counts as locked. A command handed to a shell, a wrapper or a package runner
  (`bash -c`, `timeout`, `sudo`, `npx`, `npm exec -c`, `bun exec '…'`, `pnpm dlx`) is unwrapped and
  judged, and one built at run time is refused.
- **It closes by itself.** `env` opens for 20 minutes and `db` for 15 by default, so a forgotten
  unlock does not stay open; `off` closes both at once.
- **Secrets stay out of the transcript.** The shell never reads a real `.env*` file. `show.sh` lists
  every key with secrets masked; `set.sh` changes one value while `env` is open, backs the file up
  and logs only the key name.
- **Production reads are always allowed; writes wait.** `db-guard.sh` lets one read-only statement
  through and holds anything else, including SQL it cannot parse. The server itself also starts
  read-only, because `bypassPermissions` skips `ask` rules and a text parser can be fooled by a
  function of your own that writes.

- **The operating system backs the hooks.** `.claude/settings.json` turns on Claude Code's Bash
  sandbox by default (`sandbox.enabled: true`): a sandboxed command, and anything it starts, cannot
  read `.env*` files or the backups, or write under `.claude/state/unlock/`, however its command
  line was built. Only `show.sh` and `set.sh` run outside it. The application still reads `.env`
  when it runs, so a command that needs it is retried outside the sandbox after Claude Code asks
  you (`sandbox.allowUnsandboxedCommands: false` forbids that retry). The sandbox needs macOS, or
  Linux or WSL2 with `bubblewrap` and `socat`, and not WSL1 or native Windows; where it cannot
  start, Claude Code warns and runs commands without it unless `sandbox.failIfUnavailable` is
  `true`, and the hooks stand alone. `"sandbox": {"enabled": false}` in `.claude/settings.json` or
  `.claude/settings.local.json` turns it off.

The hooks are the guardrail against slips and injected instructions (§16); the sandbox is the
boundary that holds when a command gets past them. `docs/unlock.md` says what neither stops.

---

## 22. A check that reads nothing, or less than everything, passes

A guard exits 0 both when it found nothing wrong and when it looked at nothing, and the two print
the same. It comes in two shapes:

- **A pattern that matches nothing.** A module-mock guard whose regex matches no call site in the
  whole test tree reports "all checks passed"; its count comes from the allowlist, not the scan.
- **A pipe that stops reading.** `git diff | grep -q` under `set -o pipefail` lets `grep` exit at
  the first match, `git diff` die of `SIGPIPE`, and the pipeline report failure, so the step
  prints "Clean" over the match on any diff larger than the pipe buffer.

Both pass a red-then-green test, because the green can be vacuous. The rules for a new guard
(assert it saw what must be there, fail on an empty input, print what it scanned, prove it on an
input it must catch) are in `.claude/anti-patterns/a-check-that-matches-nothing-passes.md`.
`.github/scripts/diff-scan-probes.sh` is those rules applied to the pull-request gate's diff scans.

---

## 23. The raw-SQL audit exempts by path, not by line

Interpolated `sql` is allowed in `*.repository.ts` and under `src/db/schema/`. An exemption that
filters the `+` lines of a diff by file name never matches, because a diff line does not carry its
file name, and the audit then flags exactly the files it means to allow. The audit reads the file
each hunk belongs to from its header, and the README's
[Gate details](../README.md#gate-details) describe it. Test an exemption with a file it must allow,
not only with one it must refuse.
