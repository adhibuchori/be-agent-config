## Description

## Type of Change
- [ ] feat: new feature
- [ ] fix: bug fix
- [ ] refactor: code refactor
- [ ] chore: dependency update / config change
- [ ] docs: documentation update
- [ ] test: tests

## How to Verify

<!-- The command or request that shows this working, and what a correct result
     looks like. "CI is green" is not a verification step — the gate already
     runs formatting, linting, type-checking, tests and the build, so do not
     repeat them here. -->

## Checklist

### Boundaries and contract
- [ ] Handler is thin glue with no database access; the query lives in a service
      or repository
- [ ] Errors are thrown as a `DomainError` and mapped centrally — no error body
      hand-built in a handler
- [ ] The route's `responses` map lists every status the handler can return,
      including the ones a guard produces (a 401 from an auth middleware is easy
      to forget)

### Database
- [ ] Migration generated if the schema changed, and committed in this PR
- [ ] Every filtered, sorted or joined column is indexed; foreign keys always
- [ ] `.env.<target>.example` updated if a new variable was added

### Security
- [ ] Any new state-mutating route declares an auth guard
- [ ] No secret, ID, path or upstream provider message reaches a client
- [ ] No `.env` or credential committed
