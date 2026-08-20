---
track: A
prio: 60
type: bug
blocked-by: []
summary: "Assigning a FUNCTION RESULT of interface type into TWO OR MORE elements of a LOCAL dynamic array segfaults at scope exit. One element is fine, a constructor instead of a function is fine, and a global array is fine — so the trigger is the reused hidden function-result temp meeting the routine's scope-exit cleanup."
status: done
owner: claude-acp
---

# Two function-result interfaces into a local dyn array segfault

- **Track A** (`compiler/ir.inc` call-result temp handling / `compiler/symtab.inc`
  `EmitManagedLocalCleanup`).
- Found 2026-08-20 alongside
  `bug-a-assigning-a-dynamic-array-of-interfaces-is-lowered-as-an-interface-assign`,
  and still present after that fix.

## Measured

```pascal
function Mk: IFoo; begin Result := TFoo.Create; end;

procedure P;
var d: array of IFoo;
begin
  SetLength(d, 2);
  d[0] := Mk;
  d[1] := Mk;
  d[0] := nil;
  d[1] := nil;
end;                    { SIGSEGV }
```

The axis is sharp — every one of these runs clean:

| variant | result |
| --- | --- |
| **two elements from `Mk`, local array** | **SIGSEGV** |
| two elements from `Mk`, via a `for` loop | **SIGSEGV** |
| two elements from `TFoo.Create` (constructor, not a function) | clean |
| one element from `Mk` (array still length 2) | clean |
| only `d[1]` from `Mk` | clean |
| two elements from `Mk`, **global** array | clean |
| scalar local `f := Mk; f := nil` | clean |
| local **static** `array[0..0] of IFoo` from `Mk` | clean |

The destructor, the string field and the `writeln` are all irrelevant — a plain
class with neither still crashes. FPC runs every variant clean.

## Where to look

The distinguishing ingredients are (a) a hidden caller-side temp for the
interface-typed function RESULT, (b) that temp being reused by the second call,
and (c) a routine scope exit that releases COM-interface locals. A constructor
does not go through the same result temp, a global call site has no scope exit,
and one call never reuses the temp — which is exactly the set of variants that
pass.

Note the shape rhymes with `bug-a-an-interface-passed-by-value-leaks-a-reference-per-call`
(fixed the same day): one reused temp slot, filled without releasing its previous
occupant. That one leaked; if the result temp is instead released once too often,
the same reuse produces a crash rather than a leak. Worth checking whether the
result temp is being treated as OWNED (+1 from the callee) and ALSO released at
scope exit.

Reproduce with `PXXDBG=a.ir:P` and `PXXDBG=a.arc:P` — the latter lists every
symbol the scope-exit pass considers with its `kind` / `comIntf` /
`hiddenArgTemp`, which is how the by-value-param root cause was settled.

## Root cause (measured)

`PXXDBG=a.ir:P` showed it directly. `d[0] := Mk` lowers to

```
lea   <hidden temp>
call  Mk           { hidden dest = the temp; result written there, +1 }
copy_rec d[0] <- temp      { RAW -- no retain }
```

and `PXXDBG=a.arc:P` showed the temp is an ordinary `skLocal` symbol with
`comIntf=1`, so `EmitManagedLocalCleanup` releases it at scope exit. **One
reference, two owners.** `d[0] := nil` spends it, the object is freed, and the
scope-exit release then runs on freed memory.

Not retaining the call result was *correct* — it is already OWNED (+1 from the
callee) and retaining it would over-count. The wrong half was leaving the temp
owning it as well. The destination did not need a retain; the temp needed to
stop owning.

The scalar case `f := Mk` has the IDENTICAL shape and is equally broken — its
stale release just reads harmless garbage, and its destructor counts match FPC
exactly, which is why it never surfaced. Two objects in a dyn array recycle the
block between the two releases and it faults.

## Fix

Make the move a move, in the assignment path: evaluate the call, release the
destination's OLD reference, copy the fat pointer in, then **nil the temp** so
its scope-exit release is a no-op.

Releasing the old value after the call is evaluated is safe under aliasing
because the temp holds a reference to the new value throughout — `f := Mk`
returning the object `f` already holds cannot drop it to zero there. That case is
pinned by the test (`SelfReturning`).

## Test

`test/test_interface_call_result_move.pas` — 9/9, identical to FPC. Two and then
sixteen call results into a local dyn array, a scalar local, overwrite (old
released exactly once, new survives), the self-returning aliasing case, and
static-element / record-field destinations. **The pinned binary segfaults
immediately.**

## Gate

`make compiler/pascal26` (fixedpoint, converged 1 round) + `tools/gate.sh quick`.

## Log
- 2026-08-20 — resolved, commit PENDING-COMMIT.
