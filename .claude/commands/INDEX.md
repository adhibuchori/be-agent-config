<!-- Source of Truth: _workflow-source/ -->
<!-- Sync: bash scripts/sync/workflows.sh -->

| Category | Command             | When to Use                            | Example                                |
| -------- | ------------------- | -------------------------------------- | -------------------------------------- |
| Planning | /plan               | Before every feature                   | /plan add rate limiting to auth routes |
| Quality  | /check-fix          | Quick quality gate                     | /check-fix                             |
| Quality  | /review             | Before every commit                    | /review                                |
| Quality  | /rca                | A bug whose cause is not yet known     | /rca login returns 500 after deploy    |
| Safety   | /checkpoint         | Before risky changes                   | /checkpoint before schema refactor     |
| Session  | /checkpoint-summary | Every 90min / 10 tasks                 | /checkpoint-summary auth-sprint        |
| Session  | /learn-session      | End of a session that taught something | /learn-session                         |
| Workflow | /commit             | After work is done                     | /commit                                |
| Workflow | /ship               | Finished work: review, fix, push       | /ship                                  |
| Release  | /create-pr          | Generate + create PR                   | /create-pr                             |
| Release  | /resolve-pr-review  | Triage & apply PR review               | /resolve-pr-review 42                  |
| Release  | /merge-pr           | Check readiness & merge                | /merge-pr 42                           |
| Release  | /promote            | Full dev → prod pipeline               | /promote                               |
| Release  | /promote-deploy     | Promote with CI down (no PR)           | /promote-deploy                        |
| Release  | /branch-cleanup     | After a promotion lands                | /branch-cleanup                        |
