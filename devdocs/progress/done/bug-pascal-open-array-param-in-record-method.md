---
prio: 40
---

# Open-array parameter in a record method (rejected for now — it SEGFAULTED)

- **Type:** bug (feature gap; currently a loud error)
- **Track:** P — Pascal frontend
- **Status:** done

## What
```pascal
TR = record
  function SumAll(const xs: array of Longint): Longint;   { error: not supported yet }
end;
```
FPC's `typshrdh.inc` uses one (`TRect.Union(const Points: array of TPoint)`), so that
declaration still does not parse.

## Why it is an error rather than working
It was implemented (`Params[i].IsArray := True`) and **segfaulted at the call**. An open-array
parameter needs the hidden LENGTH argument that the class/routine paths set up; registering it
with the IsArray flag alone is not enough, and the callee then reads a length that was never
passed.

Rejected loudly rather than shipped as a crash. A parse error is a bad day; a segfault in
generated code is a much worse one.

## Fix
Mirror what ParseSubroutine does for an open-array param — register the hidden high/length
parameter alongside it — in ParseRecordMethodDecl. Check `High(xs)` and indexing both work,
not just the call.

## Gate
`make test` + self-host byte-identical.

## RESOLVED 2026-07-14 (b334)
The IsArray registration is all the caller needs now — the old segfault
predated the unified call-arg path; pxx open arrays carry their length inline
at data-8. Enabled in ParseRecordMethodDecl, plus the real bug found on the
way: a `[...]` open-array LITERAL argument to ANY instance/record method was
parsed as a SET literal (crash) — the method arg loops (ParseLValueAST's and
ParseClassRecordSelectors') now fork on ParamIsOpenArrayScalar /
ParamIsVarRecArray like the plain-call path. High(), indexing, record
elements (TRect.Union shape) all pinned in test_record_method_open_array_b334.

## Log
- 2026-07-14 — resolved, commit HEAD.
