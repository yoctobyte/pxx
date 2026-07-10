---
prio: 90
---

# bug: -O2 (DEFAULT) resident param reads STALE after exception longjmp

- **Type:** bug (codegen — regcall residency, x86-64) — Track A
- **Status:** done
  (feature-opt-o3-register-pressure); affects the SHIPPING -O2 default (v194+).
- **Owner:** fable-O

## Repro

```pascal
function F(x: Integer): Integer;
begin
  try
    x := 42;
    raise EOops.Create;
  except
    on e: EOops do F := x;   { must be 42 }
  end;
end;
```

`-O0` → 42. `-O2` → returns the CALLER-passed value (7). Silent wrong answer.

## Root cause

r14/r15 param residency (feature-callconv-register-args) dual-writes stores
(frame + register), reads hit the register. The exception setjmp buf saves
r12-r15 at `try` entry and the raise longjmp RESTORES them — so a store to a
resident param inside the protected block is rolled back in the REGISTER
(the frame slot, which is authoritative, keeps the new value). Handler code
then reads the stale register.

## Fix

At `IR_EXC_ENTER` (x86-64): route the exception-taken landing through an
inline refresh block — `jz` over `<reload each resident register from its
frame slot> ; jmp handler` — so every handler entry re-syncs the register
cache with the authoritative frame before any handler code runs. Covers
nested try and finally (same EXC_ENTER path). r12/r13 -O3 scratch is
unaffected (within-statement lifetime; epilogue restores from frame slots).

## RESOLUTION 2026-07-11

Fixed as designed: `IR_EXC_ENTER` (x86-64) now routes the exception landing
through an inline refresh — `jz` over `<RegcallRefreshResident for each
resident> ; jmp handler` — when the body has resident params. Normal path
unchanged (one extra never-taken-jz only in try-bodies WITH residents); -O0/-O1
and non-x86-64 unaffected (RcResidentCount = 0 there).

Regression test `test/test_exc_resident_param.pas` (one/two residents, nested
rethrow, loop store+raise) added to the `test-opt` differential list — the
pre-fix pinned binary fails it exactly as diagnosed (7/1002/0/30 instead of
42/101202/8/40). Gates: -O2 self-host fixedpoint byte-identical, test-opt
green, make test green.

NOTE: pinned v194 carries the bug at the default -O2 — re-pin after landing.

## Log
- 2026-07-11 — resolved, commit e975489f.
