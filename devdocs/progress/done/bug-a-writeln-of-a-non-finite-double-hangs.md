---
track: A
prio: 55
type: bug
summary: "writeln() of an Inf or NaN Double HANGS (emits one space, then spins forever). FloatToStr renders the same value as 'Inf' correctly, so the correct behaviour already exists one layer away — this is writeln's own formatter"
status: done
owner: claude-AN
---

# `writeln` of a non-finite Double hangs

```pascal
program t;
var a, b, z: Double;
begin
  a := 1.0; b := 0.0; z := a / b;
  writeln(z);            { emits one space, then SPINS — killed at a timeout }
end.
```

Confirmed on `pinned` as well as HEAD, so **pre-existing**. Same for `-Inf` and
`NaN`.

## The values are fine — it is only the rendering

```pascal
if z > 1.0e300 then ...      { true:  1.0/0.0 IS +Inf }
if z < -1.0e300 then ...     { true: -1.0/0.0 IS -Inf }
if z <> z then ...           { true:  0.0/0.0 IS NaN  }
```

IEEE semantics are correct throughout. And **`FloatToStr` already renders it**:

```pascal
uses sysutils;
writeln(FloatToStr(z));      { prints `Inf` — exit 0 }
```

So the correct behaviour exists one layer away and `writeln`'s own float
formatter does not reach it. NilPy is unaffected: it renders through
`PyFloatStr`, which has the inf/nan spelling (`inf`, `-inf`, `nan`, matching
CPython).

## Why prio 55 rather than lower

The failure mode is a **HANG**, not a wrong value or a crash. A hang burns a
suite timeout slot, reads as infrastructure trouble rather than a bug, and gives
no location; it is the one failure shape worse than a segfault. Any program that
divides by zero in a float path and then prints the result stops dead — and a
float divide by zero is NOT an error condition here (it yields Inf by design,
see [[decide-int-div-zero-behavior-unification]]), so reaching this is ordinary,
not exotic.

## Where to look

`writeln`'s Double path — the digit-generation loop almost certainly has no
non-finite guard and never terminates once the exponent extraction runs on an
all-ones exponent field. `FloatToStr`'s guard is the model to copy; better still,
route both through one place so they cannot drift.

Check `Str(z, s)` and `Write` (not just `WriteLn`), and the `:w:d` width/precision
forms, before declaring it fixed — they are separate entry points.

## Gate

`make test` + self-host byte-identical, plus a Pascal test printing +Inf, -Inf
and NaN through `writeln`, `Write`, `Str` and a `:0:6` form — **with a timeout**,
so a regression to the hang fails rather than stalls the suite.

Found while measuring the current state of division by zero for
[[decide-int-div-zero-behavior-unification]]; it is not itself a div-by-zero
policy question, just the thing that happens after one.

## FIXED 2026-08-04

**FIVE formatters** had the same defect, and they disagreed about how to be wrong —
which is why fixing the first one did not make the symptom go away.

| formatter | before |
| --- | --- |
| `EmitWriteFloatSci` (x86-64 native) | **hang** |
| `EmitWriteFloatFixed` (x86-64 native) | no hang — printed `9223372036854775809.000000` |
| `PXXWriteFloatSci` (portable) | **hang** — why i386 still hung after x86-64 was fixed |
| `PXXWriteFloatFixed` (portable) | **hang** |
| `FloatToExpStr` / `StrFloat` (builtin) | **hang** — reached by `Str(F, S)` |

`FloatToStr`, sitting between the last two, **already had the guard**, and its own
header comment warned that "the normalise loop in FloatToExpStr would not
terminate on an infinity". The guard was added there and never to the routine the
comment names.

All five now answer ` Inf` / `-Inf` / ` Nan`, matching sysutils' `FloatToStr`
spelling plus the leading space the positive sign position occupies. NaN prints
UNSIGNED — `0.0/0.0` carries a set sign bit, so the check sits BEFORE the sign is
emitted, which is also what FPC does. The `:w:d` forms print the spelling rather
than a padded one: a fixed-decimals request cannot be honoured for a value with
no digits.

### Two things that cost time and are worth knowing

- **rel8 vs rel32.** The first x86-64 attempt used byte displacements. Each
  `EmitwriteChar` expands to a full write syscall sequence, so the branches span
  far more than 127 bytes and the displacement silently TRUNCATED — `Inf` came
  out right while NaN still hung, which reads like a logic bug in the NaN arm
  and is not. Every branch in these guards is rel32.
- **`writeln(x)` uses the SCIENTIFIC formatter, not the natural one.** `Nat` is
  a different entry point; chasing it first is a dead end. Confirmed by the
  output shape (` 1.0000000000000000E+000`).

NilPy is unaffected throughout: a float divide by zero raises `ZeroDivisionError`
there, matching CPython, and its rendering goes through `PyFloatStr`.

### Repin

`compiler/builtin/**` changed, and unlike promocore/pylib the compiler DOES use
`builtin.pas` — so `gate.sh`'s fixedpoint went RED with the documented
signature ([[project_builtin_change_needs_repin_for_gate_fixedpoint]]): stage A
seeds from `pinned`, which links the FROZEN builtin copy. **Proved rather than
assumed**, per that note: the `sh-A.map` / `sh-B.map` name sets are identical
except the filename header (no proc appeared or vanished) and B == C
byte-identical. `make stabilize` + `make pin` → **v243**, gate GREEN.

That pin also carries the day's other work — the promotable-int default and the
promo fixes — onto Track B/C/D's ground for the first time.

### Gate

`tools/gate.sh quick` GREEN (post-pin) + `make test` GREEN, on x86-64 and with
the output verified identical when cross-compiled to i386.
Test: `test/test_writeln_nonfinite_float.pas`, run under a **timeout** in the
Makefile — a regression here is a hang, not a wrong line.

### Still open, filed separately

Not checked: **aarch64** has its own `EmitWriteFloatNatA64` / `EmitWriteFloatSciA64`
emitters that were not touched and are very likely to have the identical loop.
Filed as [[bug-a-writeln-nonfinite-float-aarch64-emitters-unchecked]].

## Log
- 2026-08-04 — resolved, commit c070516fd.
