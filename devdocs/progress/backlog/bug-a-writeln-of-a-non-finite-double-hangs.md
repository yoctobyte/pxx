---
track: A
prio: 55
type: bug
summary: "writeln() of an Inf or NaN Double HANGS (emits one space, then spins forever). FloatToStr renders the same value as 'Inf' correctly, so the correct behaviour already exists one layer away — this is writeln's own formatter"
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
