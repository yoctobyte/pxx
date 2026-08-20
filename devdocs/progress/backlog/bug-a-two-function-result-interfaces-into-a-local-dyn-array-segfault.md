---
track: A
prio: 60
type: bug
blocked-by: []
summary: "Assigning a FUNCTION RESULT of interface type into TWO OR MORE elements of a LOCAL dynamic array segfaults at scope exit. One element is fine, a constructor instead of a function is fine, and a global array is fine — so the trigger is the reused hidden function-result temp meeting the routine's scope-exit cleanup."
status: backlog
owner: unassigned
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

## Gate

Track A: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`. Add the
case to `test/test_dynarray_of_interfaces_assign.pas`.
