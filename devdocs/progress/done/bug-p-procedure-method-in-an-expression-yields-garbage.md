---
summary: "A METHOD declared as a procedure (no result) is accepted in an expression and silently yields garbage — `n := f.DoIt` assigns stack junk, `f.DoArg(3) + 1` evaluates to 4. FPC rejects all of it"
type: bug
track: P
prio: 75
owner: claude-b-night2
---

# A `procedure` method used as a value compiles and produces garbage

- **Type:** bug — Track P (Pascal frontend, shared `compiler/parser.inc`)
- **Status:** done
- **Opened:** 2026-08-05
- **Found by:** `tools/fpc_diff_probe.sh` — the `thread-returnvalue-and-terminate`
  case wrote `writeln(t.WaitFor, ...)`. pxx's `TThread.WaitFor` is a procedure
  (FPC's is a function), so this SHOULD have been a compile error naming the
  signature mismatch. Instead it printed `136616280589680` and the probe
  reported a value divergence.

## Repro

```pascal
program pv3;
type
  TFoo = class
    procedure DoIt;
    procedure DoArg(k: Integer);
  end;
procedure TFoo.DoIt; begin end;
procedure TFoo.DoArg(k: Integer); begin end;
var f: TFoo; n: Integer;
begin
  f := TFoo.Create;
  n := f.DoIt;               writeln('assigned n=', n);
  n := f.DoArg(3) + 1;       writeln('arith n=', n);
  if f.DoIt > 0 then writeln('cmp true') else writeln('cmp false');
end.
```

pxx compiles it clean and prints:

```
assigned n=1059061768
arith n=4
cmp true
```

`arith n=4` is the informative one: the "result" of `DoArg(3)` read back as
**3** — the argument still sitting in the return register. `assigned n=` is
whatever the stack held.

FPC rejects every line:

```
pv.pas(11,17) Error: Can't read or write variables of this type
```

## Scope — methods only

A plain (non-method) procedure in the same position is rejected, so the
type-check exists and the method path bypasses it:

```pascal
procedure PlainArg(k: Integer); begin end;
n := PlainArg(3);
  -> pascal26:5: error: undefined variable (PlainArg)
```

The message is poor (it is not an undefined variable, it is a procedure used as
a value) but it is at least an error. The method call path produces no
diagnostic at all.

## Why it is urgent

This is the expensive class: no crash, no warning, a plausible wrong value far
from the cause. It also silently absorbs signature drift — the exact thing that
hid pxx's `WaitFor: procedure` vs FPC's `WaitFor: LongWord` from a probe that
was written to catch it. Any code ported from FPC that reads a result pxx's
version does not return compiles and returns junk.

## Fix (landed)

The check goes at the **tail of `ParseFactor`** — the one place that only ever
runs in expression position. A call node arriving there whose proc is not a
function is the error, unless it is a constructor.

Two things it had to get right, and only one was obvious:

1. **Constructors are `IsFunc = False` too.** Their declaration keyword is
   neither `function` nor `procedure`, so `v := TFoo.Create` looks exactly like
   the rejected case. `ProcIsConstructor` reverse-maps the proc index through
   `UMthProc_`/`UMthIsCtor`; a linear scan, which only runs for a non-function
   call and is therefore never hot. Destructors are deliberately NOT exempt.
2. **`ParseFactor` is not purely an expression path.** `ParseStatementAST`'s
   `(`-led branch parses a STATEMENT with the expression parser — `(o as T).M;`
   — so the first attempt rejected that. `StmtParenCallDepth` stands the check
   down inside that branch. Sub-expressions of such a statement lose the check;
   that is the price of a one-flag guard, and the shape is rare. **The probe
   case `as-inline-call` is what caught it** — the self-host gate, lib-test and
   34 demos were all green with the false positive in place.

Pascal only: C has its own void-value diagnostics, and NilPy's `None`-typed
calls are values by design.

## Verification

```
pascal26:12: error: "TFoo.DoIt" is a procedure and has no result to use in an expression
pascal26:9:  error: "TThread.WaitFor" is a procedure and has no result to use in an expression
```

The second is the original sighting — the shape that printed `136616280589680`
now names the mismatch.

- self-host fixedpoint converged in one round (the compiler's own ~90k lines
  contain no instance of the shape)
- `tools/gate.sh quick` GREEN including the FPC seed canary
- `tools/gate.sh lib` GREEN
- `make demos` **34/34** rebuilt with the changed compiler
- `tools/fpc_diff_probe.sh` — the set of firing `[known]` cases is byte-identical
  to the pre-change run
- new negative + positive pair in `make test`:
  `test/test_procedure_as_value_fail.pas` and `..._ok.pas`

## Gate

Track P: `make test` + self-host fixedpoint (byte-identical).

## Log
- 2026-08-05 — resolved, commit 6a7b1ee89.
