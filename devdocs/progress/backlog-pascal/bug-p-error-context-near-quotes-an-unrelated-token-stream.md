---
track: P
prio: 35
type: bug
status: backlog
found: 2026-09-01
found-by: claude-T
owner: ""
blocked-by: []
summary: "A compile error's `near:` excerpt can quote text from a completely unrelated token stream. `tgeneric50.pp` reports `pascal26:30: error: undefined variable (TTestInteger)` — line number correct — with `near: ; interface type PVarRecInt64 = ^ >>> Int64 ; PVarRecDouble`, which is RTL source with no relation to the file being compiled. The diagnostic does not error and does not look wrong; it answers about something else, which is the expensive kind of wrong."
---

# A `near:` excerpt can quote an unrelated token stream

## Repro

```
tools/../compiler/pascal26 --strict-case --strict-operator \
  library_candidates/fpc-testsuite/tests/test/tgeneric50.pp /tmp/x50
```

```
pascal26:30: error: undefined variable (TTestInteger)
  near: ; interface type PVarRecInt64 = ^ >>> Int64 ; PVarRecDouble
```

Line 30 of `tgeneric50.pp` is `t := TTestInteger.Create;` — so the **line number
is right** and the **diagnosis is right**. The `near:` context is the problem:
`PVarRecInt64` / `PVarRecDouble` are RTL declarations that appear nowhere in
`tgeneric50.pp`.

For contrast, the same compiler on the same file family produces a correct
excerpt when it does not go wrong this way:

```
pascal26:14: error: expected 'begin' before 'deprecated'
  near: < T > = class end >>> deprecated 'Message A' ;
```

## Why this is worth a ticket rather than a shrug

`near:` exists to save the reader from opening the file. When it is right it is
load-bearing; the two agents who worked `tgeneric32`/`tgeneric49` on 2026-09-01
both used it. An excerpt that is confidently drawn from another file is worse
than no excerpt: it does not error, it is not obviously wrong, and it invites
reasoning about a construct that is not there.

Same class as the stale-stamp trap that `test-selfcompile-odiff` exists to
catch, and as the `pin-shadow` verdict being read as authority — an instrument
that answers a question other than the one asked, without saying so.

## Likely shape

The error path appears to index a token buffer that is not the one for the unit
under compile — probably the RTL/system unit's, left over or shared — while the
line number comes from the correct source position. Whoever takes it: the two
outputs above are enough to bracket it, since one file produces both a correct
and an incorrect excerpt depending on which error fires.

## Note

Found while triaging `regression-test-pascal-conformance-shard0-6-4`. Not
related to that regression's cause; the residual `tgeneric50` failure that
surfaces it is the specialization-alias hint-directive gap, which is separate
again.
