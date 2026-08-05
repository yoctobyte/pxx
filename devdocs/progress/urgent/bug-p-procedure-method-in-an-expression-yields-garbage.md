---
summary: "A METHOD declared as a procedure (no result) is accepted in an expression and silently yields garbage — `n := f.DoIt` assigns stack junk, `f.DoArg(3) + 1` evaluates to 4. FPC rejects all of it"
type: bug
track: P
prio: 75
---

# A `procedure` method used as a value compiles and produces garbage

- **Type:** bug — Track P (Pascal frontend, shared `compiler/parser.inc`)
- **Status:** urgent — **silent wrong value**, no diagnostic at any stage
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

## Gate

Track P: `make test` + self-host fixedpoint (byte-identical). Track P catch —
the Pascal frontend lives in the shared `lexer.inc`/`parser.inc`, so this must
not be edited concurrently with Track A. Expect fallout: a self-hosting tree
that has been accepting this shape somewhere will start failing to compile, and
that is the fix working.
