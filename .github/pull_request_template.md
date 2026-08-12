## Description

## Type of Change
- [ ] feat: new feature
- [ ] fix: bug fix
- [ ] refactor: code refactor
- [ ] chore: dependency update / config change
- [ ] docs: documentation update

## Checklist

### Code Quality
- [ ] `bun run fl` passed (format + lint)
- [ ] `bun run type-check` passed

### Database
- [ ] Migration generated if schema changed (`bun run db:generate`)
- [ ] Migration tested locally (`bun run db:migrate`)
- [ ] `.env.<target>.example` updated if new env variable added

### API
- [ ] New endpoints have Zod OpenAPI schema
- [ ] Response shape declared in route definition
- [ ] Error cases handled in `error.middleware.ts`

### General
- [ ] No `console.log` left in code
- [ ] No `.env` or secrets committed
- [ ] BullMQ queue used for async work (not direct service call)