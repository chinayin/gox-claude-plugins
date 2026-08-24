# HTTP Service Standards (gin)

Use [gin-gonic/gin](https://github.com/gin-gonic/gin) for HTTP services.
The wire contracts (RESTful, `/v1`, snake_case, unified response body, health probes) live in
`rules.md` → "API Design" / "Microservice Governance" and are **framework-independent**;
this file is the **handler-level** standard: engine setup, handler shape, where request-scoped
values live, logging, id and trace propagation, middleware set, and testing.

## Framework

gin is **the** HTTP layer under these rules. This is not a per-project trade-off to re-open,
and there is no size threshold: "this one is small enough for `net/http`" is not a decision an
implementer gets to make. Every HTTP surface — one route or fifty, internal or public,
a webhook receiver, a debug port, a throwaway tool — is built on gin.

- Anything that serves HTTP: `github.com/gin-gonic/gin` (MUST).
- **The only exception is an explicit instruction not to use gin**, from the team or the
  project owner, recorded in the project (an ADR under `docs/`, or the task itself). An
  exception is something granted to you in writing, never something you infer from the code
  being simple.
- Track the **current release**: `go get github.com/gin-gonic/gin@latest`, and let `go.mod`
  pin the result. No version number is named here on purpose — gin's module path has no
  `/v2`, so "latest" is always a minor upgrade, never a migration.
- **`gin.New()`, never `gin.Default()`** — `Default()` attaches gin's own logger and
  recovery, which bypasses slog and emits a non-conforming error body. See "Logging".
- `net/http` + `ServeMux` is **out of scope for this standard**. Do not write new routing on
  it, and do not choose it because "the stdlib has no dependencies" — that argument trades
  one import for a hand-rolled router, middleware chain, and test harness. A service already
  on `ServeMux` is not *in violation* (this standard does not reach it), but it is not a
  model to copy either; to bring it in scope, see the last section.
- gox provides `log` / `config` / `cli` / `idgen` / `validator`. It has **no HTTP transport
  layer** — gin *is* the transport layer. Do not wait for one, do not build a router.

### gin ecosystem: what we adopt

Several of gin's most-copied idioms are forbidden below, so "follow the gin community" is not
a rule that can be applied blindly. Adopt:

- route groups; `ShouldBind*` with `binding` tags (paired with `gox/validator`)
- `gin.CustomRecovery` for panic handling (see "Middleware")
- `gin.WrapH` as a migration seam
- the official `gin-contrib` org where it does not overlap our own layers: `cors`, `gzip`,
  `pprof`
- `otelgin` for trace context; `LoggerConfig.SkipPaths` as the pattern for skipping probes

Do **not** adopt — each conflicts with a rule in this file:

- `gin.Default()` — bundles gin's logger and recovery
- `gin-contrib/zap`, `gin-contrib/logger`, or any second logging library beside slog
- `c.Set` / `c.MustGet` for business data — cannot reach layers that take `ctx`
- `gin-contrib/sessions` — its stores set cookies outside our attribute rules
- `c.SetCookie` — a positional signature cannot express `SameSite`
- `gin.CreateTestContext` — skips the router and the middleware chain

In one line: **adopt gin's routing and binding; do not adopt gin's logging, its session
handling, or its habit of using the request context as a map.**

## Engine Setup (MUST)

gin's defaults differ from `net/http` in ways that silently change externally visible
behavior. Set them explicitly at construction — an unset flag here is a production incident,
not a preference:

```go
func NewServer(addr string) *Server {
    gin.SetMode(gin.ReleaseMode)

    engine := gin.New()                  // NOT gin.Default()
    engine.RedirectTrailingSlash = false // "/v1/users/" is 404, not a 301
    engine.RedirectFixedPath = false     // no case/slash "fixing" redirects
    engine.HandleMethodNotAllowed = true // wrong method is 405, not 404
    // See "Logging" and "Request ID and Trace Propagation" for each of these.
    engine.Use(Recovery(), RequestID(), otelgin.Middleware(serviceName), AccessLog())

    srv := &http.Server{
        Addr:              addr,
        Handler:           engine,
        ReadHeaderTimeout: 10 * time.Second, // required: slowloris guard
    }
    ...
}
```

`*gin.Engine` is an `http.Handler`, so graceful shutdown stays plain
`http.Server.Shutdown(ctx)`. Keep it — do not use `engine.Run()`.

## Logging (MUST)

One logger per process, installed **once at the entry point**; `log/slog` everywhere else.
Middleware and handlers call `slog.InfoContext(ctx, ...)` and nothing else: no logger
parameter threaded through constructors, no package-level logger per package, and **never
`fmt` for logging** (`rules.md`).

### Who installs it — and who must not

`slog.SetDefault` is a **process-global, last-call-wins** store, and every `slog.InfoContext`
resolves through `slog.Default()` at call time. So the HTTP layer has no "gox logger or plain
slog?" decision to make: whatever the entry point installed **is** the default.

- The entry point (`main`, or the bootstrap it calls) calls `slog.SetDefault` **exactly once**.
- **The HTTP layer never calls `slog.SetDefault`, and takes no logger parameter.** A
  `NewServer` that installs its own logger silently overwrites whatever bootstrap installed —
  its level, its output target, and the `ContextHandler` below go with it, and every
  `request_id` / `trace_id` attribute stops appearing. There is no error and no warning: the
  last writer just wins.
- If the project's bootstrap already wires a gox logger, the HTTP layer does **nothing**.
  That is the intended end state, not a special case.
- If nothing is ever installed, `slog.Default()` is Go's built-in handler writing through the
  `log` package. Handler code stays correct; only the format and destination differ.

Corollary: **nothing outside the entry point imports `gox/log`.**

### Entry point: wiring gox in

`gox/log.Logger` **embeds `*slog.Logger`** and implements `io.Closer`, so integrating gox
means installing it as the slog default — after which every layer above it is stdlib-only:

```go
func run(ctx context.Context, cfg Config) error {
    logger, err := goxlog.New(goxlog.Options{
        Level:  goxlog.LevelInfo,
        Format: goxlog.FormatJSON,   // JSON to stdout, for k8s log collection
        Output: goxlog.OutputStdout,
    })
    if err != nil {
        return err
    }
    defer logger.Close()             // process lifetime

    // Wrap the gox handler so ctx ids land on every record (see "Request ID and Trace
    // Propagation"), and keep logger.Close() owning the resources.
    slog.SetDefault(slog.New(ContextHandler{Handler: logger.Handler()}))

    srv := NewServer(cfg.Addr)       // takes no logger, installs nothing
    return srv.Run(ctx)
}
```

Two things that look like details and are not:

- `defer logger.Close()` belongs where the **process** ends. Inside a constructor it closes
  the log file the moment that constructor returns.
- Wrap `logger.Handler()` rather than reaching for `goxlog.NewWithHandler`: the latter returns
  a plain `*slog.Logger`, so the `io.Closer` that owns the file handle is lost.

If the project does **not** already depend on gox, do not add the dependency for this — the
HTTP layer below is byte-identical either way, which is the whole point of routing through
`slog.SetDefault`:

```go
base := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo})
slog.SetDefault(slog.New(ContextHandler{Handler: base}))
```

### gin's own output must not bypass slog

gin writes framework-level output — the startup route table, warnings, recovery stack dumps —
straight to `os.Stdout` / `os.Stderr` via package variables. In a JSON-log deployment those
lines are unparseable noise that no collector will index. Redirect them **before** building
the engine:

```go
gin.DefaultWriter = slogWriter(slog.LevelInfo)       // io.Writer that forwards to slog
gin.DefaultErrorWriter = slogWriter(slog.LevelError)
gin.DebugPrintRouteFunc = func(method, path, handler string, n int) {
    slog.Debug("route registered", "method", method, "path", path, "handler", handler)
}
```

`gin.SetMode(gin.ReleaseMode)` silences most debug printing but **not** the recovery writer —
set both variables regardless of mode.

### Access log

Write your own middleware that emits slog attributes. **Do not use `gin.Logger()`,
`LoggerWithFormatter`, or `LoggerWithConfig` for the access log**: `gin.LogFormatter` returns
a `string`, so a structured record would have to be flattened into a line and re-parsed
downstream — exactly what slog exists to avoid. Do borrow gin's `SkipPaths` idea: liveness
and readiness probes fire every few seconds and must not be logged.

One record per request, carrying at minimum method, route, status, duration, and the ids from
the next section. Use `c.FullPath()` for the route — the **registered template**
(`/v1/users/:id`), never the raw URL, or log-label cardinality explodes.

## Routing (MUST)

- **All routes are registered in one place** (`cmd/<app>/run.go`), not self-registered from
  inside handler packages. Reason is security, not taste: "which endpoints are behind the
  authz middleware" must be answerable by reading one file, not by grepping ten packages.
  Avoid the `RegisterRoutes(g *gin.RouterGroup)` pattern for that reason.
- Resources are plural nouns behind a version prefix: `/v1/users`, `/v1/orders`.
- Path params use `:name`. A route match is **not** validation — the handler MUST still
  check emptiness/format of every param it reads.
- **Router-tree caveat**: gin's tree is httprouter-derived; a static segment and a wildcard
  segment as siblings (`/v1/users/export` next to `/v1/users/:id`) has historically
  panicked at registration and behaves differently across gin versions. Before adding the
  first such route, verify with a 20-line spike; if it panics, change the path shape
  (`/v1/users:export`) rather than restructuring the resource.
- Wrap legacy `http.Handler` implementations with `gin.WrapH` instead of rewriting them
  (webhook/callback endpoints are usually not worth converting).

## Handler Shape (MUST)

Struct + constructor injection + a **consumer-side minimal interface**, panicking on a nil
required dependency:

```go
// userLister abstracts the query this handler needs; *user.Repo satisfies it implicitly.
type userLister interface {
    ListUsers(ctx context.Context) ([]user.Brief, error)
}

type UserHandler struct {
    lister userLister
}

func NewUserHandler(lister userLister) *UserHandler {
    if lister == nil {
        panic("httpapi: NewUserHandler: lister must not be nil")
    }
    return &UserHandler{lister: lister}
}

func (h *UserHandler) HandleList(c *gin.Context) {
    ctx := c.Request.Context()
    items, err := h.lister.ListUsers(ctx)
    if err != nil {
        slog.ErrorContext(ctx, "httpapi: list users failed", "error", err)
        WriteErr(c, http.StatusInternalServerError, 5000, "服务内部错误，请稍后重试")
        return
    }
    WriteOK(c, gin.H{"items": items})
}
```

- Never write handlers as closures or bare functions — stubs cannot be injected, so they
  cannot be unit-tested.
- Interfaces are declared in the **consumer** (handler) package, listing only the methods
  that package uses; the repository type satisfies them implicitly.
- DTOs are defined per handler file with snake_case JSON tags. Do not return domain
  entities directly.

## Request-Scoped Values: Context, Not `c.Set` (MUST)

Authenticated identity, permission scope, request id, and trace id travel in
`c.Request.Context()`. **`c.Set` / `c.MustGet` are forbidden for business data.**

```go
func AuthMiddleware(issuer *auth.Issuer) gin.HandlerFunc {
    return func(c *gin.Context) {
        userID, err := issuer.Parse(c.Request.Context(), extractToken(c.Request))
        if err != nil {
            slog.WarnContext(c.Request.Context(), "auth: token validation failed", "err", err)
            WriteErr(c, http.StatusUnauthorized, 4011, "invalid or expired token")
            c.Abort()
            return
        }
        ctx := auth.WithUserID(c.Request.Context(), userID)
        c.Request = c.Request.WithContext(ctx) // NOT c.Set("userid", ...)
        c.Next()
    }
}
```

Three reasons, in order of weight:

1. Business and repository layers take `ctx context.Context`; only ctx reaches them without
   threading extra parameters through every signature.
2. `c.MustGet` panics on a type mismatch, while `auth.ScopeFrom(ctx) (scope, ok)` lets a
   broken middleware chain be reported as a 500.
3. Handlers stay framework-agnostic — swapping or removing gin touches only the HTTP layer.

`*gin.Context` is for HTTP-layer work only: reading params, writing the response, `Abort`.

## Request ID and Trace Propagation (MUST)

Two ids, deliberately **not** merged:

| id | scope | source | returned to the client |
|---|---|---|---|
| `trace_id` | across services | W3C `traceparent`, owned by OpenTelemetry | no |
| `request_id` | this hop | inbound `X-Request-Id`, else generated | yes — response body + `X-Request-Id` |

`request_id` is the string a user quotes in a bug report, so it must be present on every
response including errors, and must never depend on a trace sampling decision. `trace_id`
links spans across services and belongs to OpenTelemetry. Merging the two couples the
user-visible id to sampling and loses one of the two jobs.

**Reuse inbound, generate only when absent.** The gateway and calling services already issue
ids; regenerating splits one logical request into two halves that cannot be joined:

```go
func RequestID() gin.HandlerFunc {
    return func(c *gin.Context) {
        id := c.GetHeader("X-Request-Id")
        if id == "" {
            id = idgen.Generate().String() // gox/idgen, or any collision-free source
        }
        ctx := reqctx.WithRequestID(c.Request.Context(), id)
        c.Request = c.Request.WithContext(ctx)
        c.Header("X-Request-Id", id) // echo before any handler writes
        c.Next()
    }
}
```

Accessors sit beside it and return `(value, ok)` — never a panicking `MustGet`:

```go
func RequestIDFrom(ctx context.Context) (string, bool)
func TraceIDFrom(ctx context.Context) (string, bool)
```

- **Trace context is W3C `traceparent` over OpenTelemetry**, which is how `rules.md`
  ("Propagate OpenTelemetry trace context") gets implemented. Mount
  `otelgin.Middleware(serviceName)` from
  `go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin`; do not parse
  the header by hand, and do not invent an `X-Trace-Id` — a bespoke header is a standard no
  one else on the wire implements.
- **Both ids attach to every log record automatically**, through a `slog.Handler` that reads
  them from ctx. Adding them by hand at each call site guarantees that the records which
  matter most — the error paths — are the ones that forget:

```go
type ContextHandler struct{ slog.Handler }

func (h ContextHandler) Handle(ctx context.Context, r slog.Record) error {
    if id, ok := RequestIDFrom(ctx); ok {
        r.AddAttrs(slog.String("request_id", id))
    }
    if id, ok := TraceIDFrom(ctx); ok {
        r.AddAttrs(slog.String("trace_id", id))
    }
    return h.Handler.Handle(ctx, r)
}
```

  This is also why every log call takes the `*Context` form: a plain `slog.Info` carries no
  ctx and silently drops both ids. The wrapper is installed at the **entry point**, in the
  same single `slog.SetDefault` call as everything else (see "Logging") — an entry point that
  wires a logger without it produces records with no ids at all, and the HTTP layer cannot
  detect or repair that from where it sits.
- **Outbound calls carry both.** An HTTP or RPC client that drops `traceparent` /
  `X-Request-Id` terminates the trace at your service boundary. Propagate in the shared
  client, not at each call site.

## Response (MUST)

- Exactly **one** writer pair per service, matching the `rules.md` unified body:

```go
func WriteOK(c *gin.Context, data any)                              // {code:0, message:"ok", data}
func WriteErr(c *gin.Context, httpStatus, code int, msg string)      // {code, message, request_id}
```

- **Bare `c.JSON` / `c.AbortWithStatusJSON` with an ad-hoc body is forbidden.** One
  exception in one handler is enough to make response-shape drift ungreppable.
- `request_id` MUST come from the request-id middleware via ctx — never generated
  independently at the write site, or the same request reports different ids in different
  layers.
- Canonical error codes (extend this table before inventing a code):

| code | HTTP | meaning |
|---|---|---|
| `4000` | 400 | invalid parameter |
| `4001` / `4010` | 401 | unauthenticated / missing-malformed token |
| `4011` | 401 | invalid or expired token |
| `4030` | 403 | authenticated but not permitted |
| `4004` / `4040` | 404 | resource does not exist |
| `5000` | 500 | internal error |
| `5010` | 501 | not implemented |
| `5030` | 503 | dependency unavailable |

- **Never return a raw `error` to the client.** Log the cause server-side with
  `slog.*Context`; the client gets a generic human-readable message.

## Parameter Handling

- **`c.DefaultQuery` is forbidden**: it collapses "explicitly empty" and "absent", and
  endpoints do depend on that distinction. Read and branch explicitly:

```go
day := time.Now()
if s := c.Request.URL.Query().Get("date"); s != "" {
    d, err := time.ParseInLocation("2006-01-02", s, time.Local)
    if err != nil {
        WriteErr(c, http.StatusBadRequest, 4000, "date 参数格式应为 YYYY-MM-DD")
        return
    }
    day = d
}
```

- `c.ShouldBindQuery` / `ShouldBindJSON` (+ `gox/validator`) is fine for plain display
  fields. It is **not** acceptable for any value that reaches SQL.
- **Anything that becomes part of a SQL statement — sort column, dimension, metric,
  direction — MUST go through a whitelist map to a constant.** Binding tags validate
  *format*, not *domain*; never interpolate a request value into a query.
- Pagination uses cursors, not offset, for any list that can grow unbounded.

## Middleware (MUST)

Every HTTP service has these five, in this order:

1. **Recovery** — a handler panic becomes a 500 in the **unified error body**. Use
   `gin.CustomRecovery(func(c *gin.Context, recovered any) { ... })` and call `WriteErr`
   inside: it keeps gin's panic capture and its broken-pipe / connection-reset detection and
   replaces only the response body. Hand-rolled recovery middleware routinely loses the
   latter and turns a client disconnect into a logged 500.
2. **Request ID** — see "Request ID and Trace Propagation".
3. **Access log + trace** — `otelgin.Middleware` plus the slog access-log middleware from
   "Logging". slog only; never a second logging library.
4. **Auth / permission scope** — see the ctx rule above.
5. **Inbound rate limit + circuit breaker** — `rules.md` requires this for all inbound
   endpoints. Out-bound client limiters do not satisfy it.

**A middleware-contract violation is a 500, never a silent degradation.** If a handler
requires a permission scope and ctx has none, the route is missing its middleware — that is
a deployment bug. Returning empty results instead would turn a wiring mistake into a data
leak or a silent wrong answer.

## Cookies and Redirects

- Cookies: `http.SetCookie(c.Writer, &http.Cookie{...})`.
  **`c.SetCookie` is forbidden** — its positional signature cannot express `SameSite`, and
  session cookies MUST be `HttpOnly` + `SameSite=Lax` (or stricter) + `Secure`.
- Redirects: `c.Redirect(http.StatusFound, url)`.
- OAuth `state` MUST be a one-shot short-TTL cookie compared with
  `subtle.ConstantTimeCompare`, and cleared on use.

## Files and Streaming

- Prefer handing the client a **302 to a presigned object-storage URL** over proxying bytes
  through the service — it removes Range handling, timeouts, and memory pressure.
- When proxying is unavoidable, use `http.ServeContent(c.Writer, c.Request, name, modtime, rs)`
  rather than `c.File` / `c.DataFromReader`: it handles Range, ETag, and conditional
  requests correctly.

## Concurrency

- `*gin.Context` is pooled and recycled once the response is written. Any goroutine that
  outlives the handler MUST use `c.Copy()`.
- Better: **do not start goroutines in handlers.** Enqueue to the job/worker framework.
  Fire-and-forget work in a handler has no retry, no observability, and dies on deploy.
- External calls carry timeouts per `rules.md` (internal 10s, external 30s), derived from
  the request ctx so client disconnects cancel the work.

## Testing (MUST)

- Test through the engine: `engine.ServeHTTP(rec, req)` with `httptest`.
- **`gin.CreateTestContext` is forbidden.** It bypasses the router and the middleware chain
  — and a large share of a handler's contract *is* middleware behavior (missing scope → 500,
  missing token → 401). It also forces hand-filling `c.Params`, which re-introduces the
  exact "route says one thing, test says another" drift you were trying to avoid.
- Give each handler test file a small helper that registers that handler on its real route:

```go
func newTestEngine(h *UserHandler) *gin.Engine {
    gin.SetMode(gin.TestMode)
    e := gin.New()
    e.GET("/v1/users/:id", h.HandleDetail)
    return e
}
```

- Integration smoke tests use `httptest.NewServer(engine)`.

## Bringing an Existing `net/http` Service In Scope (conditional)

Migration is how a `ServeMux` service stops being out of scope. It is worth doing when the
service is actively developed; it is not worth doing to a frozen one.

Only as a **standalone branch**, never alongside feature work — it touches every handler
and every handler test, so it conflicts with everything.

Measured on a real service (29 routes, 35 handlers, 2.9k lines of handler code, 4.3k lines
of handler tests): **~2.5–3 person-days**. The cost driver is not the handlers; it is the
test call sites that invoke handlers directly as `h.HandleX(rec, req)`.

Order that keeps every intermediate commit green:

1. Add Recovery / request-id / access-log middleware **first**, still on `net/http`. Those
   are required anyway, and having recovery in place before the churn means a mistake in a
   later step is a 500 instead of a dropped connection.
2. Swap the engine internals to gin but keep the existing
   `Handle(pattern string, handler http.Handler)` seam, translating `{x}` → `:x` and
   wrapping with `gin.WrapH`. After this commit every handler, middleware, and test is
   untouched and still passing — gin's introduction is confined to one file.
3. Add the gin-flavored `WriteOK` / `WriteErr` beside the existing pair, reusing the same
   body structs so both eras are byte-identical.
4. Convert the middlewares, keeping identity in `c.Request.Context()` (see above). This is
   what keeps step 5 from doubling in size.
5. Convert handlers **one file per commit**, smallest first, dropping each route's
   `gin.WrapH` as its file lands.
6. Convert the tests, then delete the compatibility seam. Verify `gin.DefaultWriter` is not
   writing to stdout and that Recovery emits the unified body.

Semantic differences to close deliberately — each one is an externally visible change:

| behavior | Go 1.22 `ServeMux` | gin default | required setting |
|---|---|---|---|
| wrong method on a known path | **405** | 404 | `HandleMethodNotAllowed = true` |
| trailing slash | 404 | **301 redirect** | `RedirectTrailingSlash = false` |
| case / duplicate slashes | 404 | **301 redirect** | `RedirectFixedPath = false` |
| static + wildcard siblings | supported (static wins) | **may panic at registration** | spike first |
| handler panic | connection drops | 500, non-conforming body | `gin.CustomRecovery` |
| access log | none | `gin.Default()` writes to stdout | `gin.New()` + slog |

Grep the frontend for `405` / `404` branching before flipping the first two.
