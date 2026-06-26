# feature: typed constant record initializer (`const r: TRec = (...)`)

- **Type:** feature (Track A — parser)
- **Status:** DONE 2026-06-23 (commit ef757ef)

## Resolution (2026-06-23)

`const r: TRec = (f1: v1; f2: v2; ...)` (FPC named-field) parses for global and
routine-local consts; mixed field types verified (`7` / `10 Z 20` / local `300`
re-init per call). Each scalar field records a `sym.field := value` init via the
existing Pending/Local-init machinery — new `PendingInitFOff/FLen` +
`LocalInitFOff/FLen` carry the field-name source span, which the init emitter
turns into an `AN_FIELD` target (else array-index, else scalar). `AllocVar`
already sizes/tags the record slot. Fields separated by `;` (trailing `,`
tolerated). Front-end only; self-host byte-identical; `make test` green.

Test: `test/test_typed_const_record.pas`. **Not pinned** (no Track B request);
pin on demand. Follow-up: nested record/array field values, and string-valued
fields (ParseInitVal is ordinal/float-bits only today).

---

(original below)

- **Status (orig):** backlog
- **Found:** 2026-06-23, differential probe vs FPC
- **Severity:** low-medium (sibling of typed-const-arrays; explicitly out of its scope)
- **Relation:** `feature-typed-const-arrays` (done) lists "record-initializer
  constants" as out of scope — this is that follow-up.

## Gap

A record-typed constant with a field initializer does not parse:

```pascal
type tr = record x, y: integer; end;
const o: tr = (x: 3; y: 4);
begin writeln(o.x + o.y); end.
{ fpc: 7    pxx: error at SrcLine ...: SVal = x Kind = 1 (parse fails at the initializer) }
```

Typed const arrays (`const a: array[0..2] of integer = (10,20,30)`) and scalar
typed consts already work.

## Expected

Parse `const Name: <recordtype> = (field: const; field: const; ...)` (FPC named
field syntax), stored like other typed constants. Nested records/arrays ideally.

## Repro

`tools/fpc_diff_probe.sh` (`const-record`).
