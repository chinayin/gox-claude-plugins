# Time and Timezone Standards (Go + GORM)

Applies when time is **persisted or crosses a system boundary** (DB columns, DSN,
external timestamps, API fields, daily cutoffs) — in-process time needs none of
this. §1/§3 apply to any engine; §2/§5/§6 are MySQL (any version), with the SQLite
note in §2. New table: checklist §9. Migration mechanics:
`references/db-migrations.md`.

## 1. Core Invariants (everything else is a corollary)

1. **Absolute instants are always stored as UTC.**
2. **Only the application writes time** — no `DEFAULT / ON UPDATE CURRENT_TIMESTAMP`
   on any column.
3. **Conversion happens only at the boundaries**: parse into `time.Time` at the
   entrance, format to RFC3339 at the exit, never touch timezones in between.
4. **A timezone is data, not environment**: an IANA field in the database — never
   inferred from server, data center, or request origin.

Real cost of violating (anonymized): two clocks wrote the same column, the column
was used as evidence of authenticity, legitimate users were ruled forgers.

## 2. Storage Types (MySQL)

| Type | Ruling | Why |
|---|---|---|
| `DATETIME` storing UTC | Default for business tables | Human-readable, computable in SQL, driver converts with zero code |
| `BIGINT` epoch millis | Exceptions only | High-throughput event/message streams; machine-only consumers; fields passing through Redis/Kafka/ClickHouse untouched |
| `TIMESTAMP` | Forbidden | Reads/writes float with the session timezone; 2038 ceiling |

Why: `DATETIME` stores a bare literal — "it's UTC" holds only by convention, hence
the single-writer rule. `TIMESTAMP` converts per session timezone both ways. No
MySQL type remembers a timezone; mixed conventions in a column are unrecoverable.

**Consumers choose the storage format, not the producer.** "Upstream gives epoch"
justifies one `time.Unix` at the entrance, not epoch storage — stored data is read
hundreds of times by SQL/BI/debugging, where epoch drags `FROM_UNIXTIME`
(session-timezone-dependent) into every query. Epoch's places: boundary input
format; sort keys / pagination cursors of message-stream tables.

- Precision: `DATETIME` (seconds); `DATETIME(3)` or epoch millis when intra-second
  ordering matters.
- **SQLite**: no native time types, no session timezone — §5/§6 traps don't exist,
  invariants unchanged: store UTC (text or epoch, one convention per column),
  application writes all values.

## 3. Three Kinds of Time Semantics (classify before choosing a type)

| Semantics | Store as | Examples |
|---|---|---|
| Absolute instant (physical moment) | UTC + `DATETIME` | `created_at`, `paid_at` |
| Calendar date ("which day", business terms) | `DATE` + comment naming the timezone | `stat_date` |
| Future local time ("9:00 every day") | Local time + IANA name; **never UTC** | cron config, reminders |

- Never `DATE()` a UTC instant into a calendar date — convert to the business
  timezone first (for UTC+8, events between 00:00–08:00 otherwise land on the
  previous day).
- Future local times converted to UTC break when DST shifts.

## 4. Go Boundary Rules

`time.Time` = absolute instant + a Location label. The label affects only printing
and date truncation; `.UTC()` / `.In(loc)` swap the label, never the instant.

| Input | Rule |
|---|---|
| epoch | `time.Unix(sec, 0)` / `time.UnixMilli(ms)`. Unambiguous; ±8h "corrections" forbidden. Seconds vs millis: check docs per endpoint — vendors mix them |
| String with offset (RFC3339) | `time.Parse(time.RFC3339, s)` |
| **String without offset** | **`time.ParseInLocation` + explicit source timezone.** Bare `time.Parse` silently assumes UTC — 8h wrong for implicit UTC+8 strings |

- Date truncation requires `.In(businessTZ)` first — otherwise the result depends
  on the server timezone.
- `time.Local` forbidden in business code. The business timezone comes from one
  converged package — exactly one place defines the Location; scattered
  `time.LoadLocation` forbidden.
- Don't fix labels before persisting: a correct instant is enough, the driver
  normalizes (§5).

## 5. Driver and GORM Mechanics

The driver is the safety net: go-sql-driver converts any label per the DSN's `loc`
on write and parses back on read (`parseTime=true`). With `loc=UTC`, every machine
writes the same UTC literal — no formatting code.

GORM performs **no timezone conversion**; it only auto-fills time fields on some
paths:

| Write path | `autoCreateTime`/`autoUpdateTime` applied? |
|---|---|
| `Create()` / `Save()` | Yes |
| `Model(&X{}).Updates(...)` (struct or map) | Yes |
| upsert `DoUpdates` whitelist | **No** — not listed = not written |
| `Table("x").Updates(...)` | **No** — no model type info; use `Model(&X{})` or fill manually |
| Raw SQL | **No** — hand-write `updated_at = UTC_TIMESTAMP()` |

The three "No" rows cause real incidents. Two defenses: (1) a `Before("gorm:create")`
callback appends the `autoUpdateTime` column to any statement carrying
`OnConflict.DoUpdates`; (2) no column defaults (§1-2) — a missed INSERT fails
loudly with `ERROR 1364` instead of silently writing the wrong timezone.

Raw SQL uses `UTC_TIMESTAMP()`, never `NOW()` (session-timezone dependent).

## 6. DSN and Deployment

Exactly one DSN reaches the driver — GORM adds no defaults and passes it through.
Absent params fall to driver defaults: `Loc=UTC`, `parseTime=false` (loud failure),
`time_zone` **unset** — the session then follows the server's global. Never trust
a config-supplied DSN as-is; pin the convention **once, in the shared DB bootstrap**:

```go
cfg, err := mysql.ParseDSN(dsnFromConfig) // github.com/go-sql-driver/mysql；err 处理略
cfg.ParseTime = true
cfg.Loc = time.UTC // 驱动侧口径
if cfg.Params == nil {
	cfg.Params = map[string]string{}
}
cfg.Params["time_zone"] = "'+00:00'" // 会话侧口径；FormatDSN 负责转义
db, err := gorm.Open(gormmysql.Open(cfg.FormatDSN())) // gormmysql = gorm.io/driver/mysql
```

- Code wins over config: missing/mis-written params are normalized, others pass
  through. An unavoidable literal DSN is pasted verbatim
  (`...&loc=UTC&time_zone=%27%2B00%3A00%27`), never retyped.
- `loc` = driver-side conversion. `time_zone` = session side, and the backstop for
  non-compliant code: a stray `NOW()` or leftover `DEFAULT CURRENT_TIMESTAMP`
  evaluates at `+00:00` and still writes UTC — consistent, not mixed.
- **The DSN reaches only this app's sessions.** Foreign writers (another project's
  unpinned DSN, `NOW()` in a GUI client, stored procedures) follow the **server
  global** `time_zone` — on databases created under this standard, pin the global
  to `'+00:00'` too. Never flip the global on a legacy local-offset database: it
  shifts `TIMESTAMP` and `NOW()` for every consumer. An explicit foreign `NOW()`
  is governance: one database, one owning service; manual ops SQL uses
  `UTC_TIMESTAMP()`.
- Server/container `TZ` carries no semantics — pin UTC for log correlation. The
  business timezone is data (§1-4), used only at the outermost layer.
- Remaining leaks: local-label date truncation (§4); schedulers — cron "9:00
  daily" fires per machine timezone, declare it explicitly; NTP drift.
  Multi-source: every DSN declares its source's convention (legacy UTC+8 literals
  → `loc=Asia/Shanghai`).

## 7. API Contract

API format and storage format are independent decisions.

- Responses: RFC3339 UTC everywhere (`"2026-08-26T07:00:00Z"`). With `loc=UTC` the
  driver returns `time.Time` labeled UTC, so `encoding/json` emits the `Z` form
  with zero code (`.UTC()` only when hand-formatting). Never return strings
  pre-formatted for a timezone — rendering is the frontend's job.
- Absolute-instant inputs: offset-carrying RFC3339 (`"...T15:30:00+08:00"`).
- Calendar-date / wall-clock inputs: literal + timezone name
  (`{"date":"2026-08-26","timezone":"Asia/Shanghai"}`) — converting to UTC shifts
  the day.
- Frontend converges on one formatting utility (dayjs + user timezone); scattered
  `new Date().toLocaleString()` forbidden.

## 8. Globalization Notes

- DST-observing timezones cannot serve as storage conventions (literals repeat one
  hour every autumn). A fixed offset like UTC+8 is self-consistent but must be
  re-declared at every boundary forever; UTC is the tooling default. **This
  standard fixes UTC as the sole storage convention.** A non-global product
  choosing a fixed offset instead is a team-level ADR — and still pins it in every
  DSN (`loc` + `time_zone`), never inherited from the server.
- Daily-cutoff aggregation follows the market/tenant timezone, never the server's;
  prefer IANA conversion in the application layer (`CONVERT_TZ` named zones depend
  on per-cloud timezone tables).
- Cross-region merging/reconciliation works only because every region shares UTC.

## 9. New-Table Checklist

- [ ] Every time column classified into one of §3's semantics; type chosen accordingly
- [ ] Absolute instants: `DATETIME` (or `DATETIME(3)`) + `NOT NULL`, **no**
      `DEFAULT / ON UPDATE CURRENT_TIMESTAMP`
- [ ] Calendar dates: `DATE` + COMMENT naming the business timezone
- [ ] Future local times: two fields — local time + IANA timezone name
- [ ] `CreatedAt`/`UpdatedAt` follow GORM naming so auto-timestamps apply
- [ ] Upsert / bare-UPDATE write paths go through `Model()` and are covered by the
      callback (§5)
- [ ] Migrations pass the static check: no `DEFAULT / ON UPDATE CURRENT_TIMESTAMP`
      (CI grep gate recommended)
- [ ] (New database) server global `time_zone` pinned to `'+00:00'` — the backstop
      for sessions the DSN can't reach (§6)
