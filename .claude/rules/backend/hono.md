# Hono + `@hono/zod-openapi` Patterns

`AGENTS.md` §B/§C (layer boundaries, error contract) and §I (Rules 38–41, runtime hardening)
are the enforced, numbered versions — read those first. This file is the deeper reference.

## Router creation

> This repo has **no `src/lib/factory.ts`** — see AGENTS.md Compliance Status. Each module
> creates its own `new OpenAPIHono()` and the `defaultHook` lives once on the root app in
> `src/app.ts`. Follow that until the factory is ported; the fleet target is below.

```ts
// today, in <module>.routes.ts
import { OpenAPIHono } from "@hono/zod-openapi";
export const thingApp = new OpenAPIHono();

// fleet target, once src/lib/factory.ts is ported from the admin-dashboard repo:
// import { createRouter } from "../../lib/factory.ts";
// const thingApp = createRouter();   // wires defaultHook + AppEnv in one place
```

## Route definition

`createRoute()` from `@hono/zod-openapi`, bound via `router.openapi(route, handler)`. The
route owns the OpenAPI contract — path, method, request schemas, and every response including
error responses:

```ts
export const getThingRoute = createRoute({
  method: "get",
  path: "/things/{id}",
  request: { params: z.object({ id: z.string() }) },
  responses: {
    200: { content: { "application/json": { schema: thingResponseSchema } }, description: "OK" },
    // Rule 13: declare every status the handler can return. Becomes
    // ...errorResponses(404, 422) once src/lib/problem.ts is ported.
  },
});
```

Do not write a `HEAD` route. Hono answers HEAD by running the GET handler and stripping the
body; a dedicated HEAD handler never executes.

## Handlers

Typed `RouteHandler<typeof route>` today (there is no `AppEnv` here yet — see Compliance
Status). Once `src/lib/factory.ts` is ported, the second type parameter becomes required, or
`c.env` type-checks against Hono's bare `Env` instead of `AppEnv` and everything downstream
(`requestId`, session, future context vars) loses its type. `@hono/zod-openapi` supports this
fully — do not reach for `hono-openapi`'s `describeRoute()` + `as never` workaround; that's a
different library's typing gap that doesn't apply here.

```ts
export const getThing: RouteHandler<typeof getThingRoute> = async (c) => {
  const { id } = c.req.valid("param");
  const thing = await getThingById(id); // service call
  return c.json(thing, 200);
};
```

Handlers stay ≤15 lines (Rule 28). Rule 11 (never hand-build an error body) is the target;
today `courses.handler.ts` still returns `{ success, error }` inline for 404 — match that
existing envelope rather than inventing a third one, and declare it in the route's `responses`.

Do not build Rails-style controller classes. If a route needs shared middleware plus a handler,
compose them with Hono's `createFactory().createHandlers(...)` rather than inventing a
controller layer — the module's service is already the place logic lives.

## Middleware

`createMiddleware()` from `hono/factory`, parameterised with the variables it reads — see
`src/middlewares/logger.middleware.ts`, which declares `<{ Variables: RequestIdVariables }>` so
`c.get("requestId")` type-checks. Once `src/lib/factory.ts` is ported this becomes
`factory.createMiddleware()` and the parameter disappears.

## Middleware order in `app.ts` (Rule 41)

The order is part of the contract, not a preference. It is documented inline in `src/app.ts`;
the reasoning:

| Position | Middleware | Why here |
|---|---|---|
| 1 | `requestId()` | Everything below must be able to log the correlation id |
| 2 | `secureHeaders()` | Must be in place before any response body can be produced |
| 3 | `cors({ origin: env.CORS_ORIGINS })` | Reject a disallowed origin before spending work. **Never a bare `cors()`** — that sends `Access-Control-Allow-Origin: *` (Rule 39) |
| 4 | `requestLogger` | Correlation exists by now, so the log line carries it |
| 5 | `bodyLimit` (`/api/*`) | Reject an oversized payload before reading it |
| 6 | `timeout` (`/api/*`) | Cap total handler time |
| 7 | `rateLimiter` (`/api/*`) | Last, so a request already rejected above never consumes quota |

`bodyLimit`'s default `onError` throws an `HTTPException` carrying its own plain-text 413
`Response`, which the error handler would render with a generic message — `app.ts` passes an
explicit `onError` that throws a message-only `HTTPException(413)` so the response body stays
meaningful. `timeout()` already throws a message-carrying 504, so it needs no equivalent. Both
land in `app.onError`, so the request budget does not punch a hole in the error envelope.

`app.onError` is registered once, globally, above the route mounts — Hono resolves it at
request time regardless of ordering, but keeping it there keeps `app.ts` readable top-to-bottom
as "policy, then routes". There is no `app.notFound` here yet: an unmatched route returns
Hono's plain-text 404, which is the one hole left in the error envelope until §C lands.

## Caching and large responses

- For a response that is expensive to build and safe to revalidate, add `etag()` on that route
  group — Hono answers a matching `If-None-Match` with 304 and no body.
- Data-level caching (Redis cache-aside) belongs in the service, not in middleware; see
  `.claude/rules/backend/performance.md`.
- For a genuinely large payload, stream (`stream`/`streamText` from `hono/streaming`) rather
  than materializing the whole body — but first check whether the endpoint should have been
  paginated (Rule 29). Streaming an unbounded result set is still an unbounded read.

## OpenAPI spec generation

`app.doc("/openapi.json", {...})` is called once, in `src/index.ts` (bootstrap), not in
`app.ts` (composition) — the OpenAPI document metadata (title/version/description) is a
bootstrap concern, not part of the request-handling composition.
