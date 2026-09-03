# Go Code Style: Shaping Code

Companion to `references/rules.md`. Read when reducing complexity, laying out a new
package, or designing options, structs, interfaces or generics. Rulings are in
`rules.md`; this file holds the patterns and examples behind them.

## Complexity patterns

Reshape code instead of suppressing lint.

### Pattern: Early return to separate branches

```go
// Bad - dry-run and real logic mixed in one loop
func apply(items []Item, dryRun bool) {
    for _, item := range items {
        if dryRun {
            // dry-run logic...
            continue
        }
        // real logic... (nesting +1)
        result := doApply(item)
        switch result.Action {
            // nesting +1 again...
        }
    }
}

// Good - split into independent paths
func apply(items []Item, dryRun bool) {
    if dryRun {
        printDryRun(items)
        return
    }
    results := doApplyAll(items)
    printSummary(results)
}
```

### Pattern: Extract print/format helpers from loops

```go
// Bad - switch nested inside loop, function bloats
for _, item := range items {
    result := apply(item)
    switch result.Action {
    case "created":
        fmt.Printf(...)
        created++
    case "updated":
        fmt.Printf(...)
        for _, c := range result.Changes { ... }
        updated++
    }
}

// Good - extract display logic
for _, item := range items {
    result := apply(item)
    printResult(item, result)
    countByAction(result, &created, &updated)
}
```

### Pattern: Merge similar switch cases

```go
// Bad
case "updated":
    updated++
case "applied":
    updated++

// Good
case "updated", "applied":
    updated++
```

## Package file organization

Standard layout (`rules.md` → "Package File Organization"):

```
doc.go      - package documentation
const.go    - constants shared across files (referenced by multiple files in same package)
errors.go   - package-level errors (Err prefix, with comments)
types.go    - shared types first, then constants
<impl>.go   - implementation, file-local constants declared at top of file
```

### Constant placement

- Used by multiple files in same package -> centralize in `const.go`
- Used only in current file -> declare at top of that file, keep colocation for decoupling
- Judge the constant's scope and place it accordingly

### Example

```go
// doc.go - package documentation
// Package storage provides multi-cloud storage abstraction.
package storage

// errors.go - package-level errors (only definitions, each with comment)
package storage

import "errors"

var (
    // ErrNotFound indicates resource does not exist
    ErrNotFound = errors.New("storage: resource not found")
)

// types.go - shared types first, then constants
package storage

type Client interface {
    Download(ctx context.Context, path string, w io.Writer) error
}

const (
    TypeS3  = "s3"
    TypeOSS = "oss"
)

// s3.go - implementation with file-local constants at top
package storage

const (
    s3DownloadTimeout = 30 * time.Minute
    s3UploadTimeout   = 30 * time.Minute
)

func (c *S3Client) Download(ctx context.Context, path string) error {
    obj, err := c.getObject(ctx, path)
    if err != nil {
        return fmt.Errorf("storage: get object %q: %w", path, err)
    }
    return nil
}
```

## Functional Options

Use when 3+ optional parameters:

```go
type Option func(*Client)

func WithTimeout(d time.Duration) Option {
    return func(c *Client) { if d > 0 { c.timeout = d } }
}

func NewClient(endpoint string, opts ...Option) *Client {
    c := &Client{endpoint: endpoint, timeout: 30 * time.Second}
    for _, opt := range opts { opt(c) }
    return c
}
```

## Struct Design (SHOULD)

- Field order: embedded -> exported -> unexported
- Group related fields with blank lines
- Never store Context in structs
- Receiver name: type initial (`c *Client`, `s *Server`)
- Pointer receiver if mutating or has sync.Mutex

```go
type Client struct {
    *BaseClient  // embedded

    endpoint string  // core config
    bucket   string

    timeout time.Duration  // connection config
    mu      sync.RWMutex   // internal state
}
```

## Interface Design (SHOULD)

- Small and focused (single responsibility)
- Name with `-er` suffix: Reader, Writer, Closer
- Define at consumer side, not implementor
- Prefer stdlib interfaces: io.Reader, io.Writer

```go
// Good - small and focused
type Downloader interface {
    Download(ctx context.Context, path string, w io.Writer) error
}

// Bad - too large
type Storage interface {
    Download(...) error
    Upload(...) error
    Delete(...) error
    List(...) ([]string, error)
    Copy(...) error
    Move(...) error
}
```

## Generics (SHOULD)

- Use for generic data structures: Stack, Queue, Set
- Use for collection operations: Map, Filter, Reduce
- Avoid over-genericizing business logic

## Pitfall examples

Rulings in `rules.md` → "Common Pitfalls"; the shapes behind them:

### Design for zero-value usability

```go
// Good - zero value is usable
type Buffer struct {
    buf []byte
}

func (b *Buffer) Write(p []byte) (int, error) {
    b.buf = append(b.buf, p...)  // nil slice can append
    return len(p), nil
}

var buf Buffer  // usable without initialization
buf.Write([]byte("hello"))
```

### Avoid package-level mutable state

```go
// Bad - package-level mutable state
var globalClient *http.Client

// Good - dependency injection
type Service struct {
    client *http.Client
}

func NewService(client *http.Client) *Service {
    return &Service{client: client}
}
```
