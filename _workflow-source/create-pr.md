---
description: Detect branch context, draft a PR title and description, and open the PR.
---

<!-- Command: /create-pr -->
<!-- Source: _workflow-source/create-pr.md -->

# /create-pr — Create Pull Request

## Step 0: Detect Context

```bash
git branch --show-current
git log dev..HEAD --oneline
git diff dev..HEAD --stat
```

The base branch is **`dev`**, never `main` — this repo promotes `internal/{scope}` → `dev` →
`prod`.

## Step 1: Collect What Is Missing

Ticket ID (optional), one-sentence feature description, any breaking change or migration note.

## Step 2: Draft

**Title:** `feat(scope): [TICKET-ID] {Description In Title Case}` — under 70 characters.

**Description:**

```
**📝 Description**
[What problem does this solve?]

**🛠️ Technical Implementation**
[Layers touched, key files, architectural decisions.]

**✅ Testing**
[How this was verified.]

**📋 Checklist**
- [ ] Format + lint passed (`bun run fl`)
- [ ] No TypeScript errors (`bun run type-check`)
- [ ] Production bundle builds (`bun run build`)
- [ ] Migration generated and committed, if `src/db/schema/` changed
- [ ] Every FK column indexed (`bash scripts/check-index-coverage.sh`)
- [ ] `openapi.json` regenerated (`bun run spec:export`) if routes or schemas changed
- [ ] No `//` comments outside the directive allowlist
```

## Step 3: Confirm

Show title and body. Ask whether they are correct before creating.

## Step 4: Create

```bash
gh pr create --title "<title>" --body "<body>" --base dev
```

Output the PR URL.
