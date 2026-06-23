# feature: typed constant record initializer (`const r: TRec = (...)`)

- **Type:** feature (Track A — parser)
- **Status:** backlog
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
