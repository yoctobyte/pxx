---
track: A
prio: 60
type: bug
blocked-by: []
summary: "A COM interface passed BY VALUE leaked one reference per call. The caller's argument temp is a single stack slot reused by every execution of the call site, and it was filled with a raw copy_rec + retain — so each call overwrote the previous occupant without releasing it. Five constructions, one destruction; from the main body, ZERO destructors ran for five objects. `const` and `var` params were always correct, which is what hid it."
status: done
owner: claude-acp
---

# An interface passed by value leaks a reference per call

- **Track A** (`compiler/ir.inc`, `IRLowerCallArg` — shared core, not the P frontend).
- Found 2026-08-20 by an FPC differential probe of the interface/ARC surface.

## Measured

`fpc -O- -Mobjfpc` vs pxx at the pinned binary:

```pascal
procedure TakeVal(a: IFoo); begin a.Bump; end;
...
for i := 1 to 5 do
begin
  f := TFoo.Create;
  TakeVal(f);
  f := nil;
end;
```

| where the call is made | FPC | pinned pxx |
| --- | --- | --- |
| inside a routine, checked after it returns | 5 constructed / 5 destructed | 5 / **1** |
| from the main program body | 5 / 5 | 5 / **0** |
| `const a: IFoo` | 5 / 5 | 5 / 5 |
| `var a: IFoo` | 5 / 5 | 5 / 5 |

The leak grows with the loop count — it is unbounded, not a fixed overhead.

## Cause

A by-value interface argument gets a private caller-side temp. That temp is
**one stack slot**, reused by every execution of the call site. It was filled
with a raw `IR_COPY_REC` and then retained with `PXXIntfAddRef`, so each
execution **overwrote the previous occupant without releasing it** and that
reference went on the floor. Only the final occupant was ever released, by
`EmitManagedLocalCleanup` at the caller's scope exit.

From the MAIN body there is no scope exit at all, so even the last occupant was
held forever — which is why the pinned binary ran zero destructors there.

`const` never reaches this path (it stays a by-ref alias of the caller's slot,
no copy and no refcount, matching FPC), and `var` likewise. **Two of the three
parameter modes were correct** — the `normalise-dont-special-case` shape, and
the reason this survived: every hand-written interface test used `const`.

## Fix

Two parts, both in `IRLowerCallArg`:

1. Fill the temp with **`PXXIntfAssign`** (retain source, release old dest, copy
   — in that order, which is what makes it safe when dest and src alias) instead
   of hand-rolling `copy_rec` + `PXXIntfAddRef`. The primitive already existed
   and already had the right semantics; the bug was not using it.
2. Mark the temp `SymIsHiddenArgTemp` so codegen nil-inits the slot, because the
   release in (1) would otherwise free stack garbage on the first execution —
   the identical hazard, and the identical remedy, already documented three
   lines above for a managed-field record temp.
3. Record a main-body (skGlobal) temp in `MainBodyIntfTempSym` for the
   program-exit release pass, exactly as `IRMaterializeIntfCast` already did for
   an as-cast temp.

## The wrong root cause this nearly got

The first diagnosis was "the temp escapes `EmitManagedLocalCleanup`" — plausible,
because the main-body variant genuinely is `skGlobal` and genuinely is skipped.
It was **wrong**, and reasoning could not have told me so: the epilogue releases
are emitted as machine code, not IR, so `a.ir` shows an AddRef with no matching
Release and looks like proof.

Added `PXXDBG=a.arc:<proc>` (`compiler/symtab.inc`, documented in
`devdocs/dev/debug-switches.md`) — it prints every symbol that pass considers
with `kind` / `comIntf` / `hiddenArgTemp`. It showed the temp was `skLocal`,
flagged as a COM interface, and **not** skipped. That killed the wrong story and
pointed at the loop overwrite instead.

Second lesson, same session: an intermediate probe printed `destroyed=0` from
*inside* the owning routine and read as a total leak. It was a scope-exit timing
artefact. Print the count after the routine RETURNS, or count destructor lines
after the process ends — which is what the regression test does.

## Left open

pxx releases the temp at the **caller's** scope exit; FPC releases it at
**callee return**. Every object is still destroyed exactly once, but the last of
a batch dies later than under FPC. Split out as
`bug-a-a-by-value-interface-param-is-released-at-caller-scope-exit` rather than
half-fixed here — it is an ownership-model change (caller-temp vs callee-owned)
that touches every `IRLowerCallArg` call site.

## Test

`test/test_interface_byval_param_no_leak.pas` — 16/16, byte-identical to FPC's
output. Covers 1 / 5 / 50 calls, `const`, `var`, the same reference in two
parameters (which is what exercises PXXIntfAssign's retain-before-release
order), and nested call sites. **The pinned binary scores 12 / 16.**

## Gate

`make compiler/pascal26` (fixedpoint, converged 1 round) + `tools/gate.sh quick`.
