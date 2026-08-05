---
track: A
prio: 45
type: bug
summary: "sqrt/sin/cos/exp/ln/arctan require `uses math`; in FPC they are System-unit intrinsics available with no uses clause. Loud (undefined variable), but it breaks unmodified FPC/Delphi source on its first line"
status: done
owner: claude-A
---

# `sqrt`, `sin`, `cos`, `exp`, `ln`, `arctan` are not available without `uses math`

- **Type:** compat (FPC/Delphi parity, **compat-pascal-\*** tag) — **Track A**
  (the builtin/System surface is A's ground)
- **Found:** 2026-08-02 by an extended differential sweep against the FPC oracle.
- **Loud**: `error: undefined variable (sqrt)`.

## Measured

```pascal
program p;
begin writeln(sqrt(16.0):0:1); end.
```

```
FPC: 4.0
pxx: error: undefined variable (sqrt)
```

Adding `uses math;` makes it work and the output then matches FPC exactly
(`4.0`). The same applies to the whole group:

```pascal
begin writeln(sin(0.0):0:1,'|',cos(0.0):0:1,'|',exp(0.0):0:1,
              '|',ln(1.0):0:1,'|',arctan(0.0):0:1); end.
```

```
FPC: 0.0|1.0|1.0|0.0|0.0
pxx: error: undefined variable (sin)
```

`abs`, `sqr`, `trunc`, `round`, `int`, `frac`, `odd`, `inc`, `dec`, `chr`, `ord`,
`succ`, `pred`, `str` and `val` are all present with no uses clause and all agree
with FPC, so this is specifically the transcendental/`sqrt` group.

## Why it is worth fixing despite being loud

These six are **System-unit** routines in both FPC and Delphi — `math` adds
`power`, `logn`, `ceil`, `floor` and friends *on top* of them, it does not own
them. So any unmodified real-world Pascal source that computes a distance, a
norm, or an angle fails to compile with no hint that a `uses` line is missing,
and the fix a reader would reach for (adding `uses math`) is not what the
original source says.

It also lands on the first line that matters, which makes it a poor first
impression for the corpus-compat work: a file that is otherwise fully supported
is rejected outright.

## Fix

Declare the six in the builtin/System surface alongside the arithmetic
intrinsics already there, and keep `math`'s own exports working — a program with
`uses math` must still compile, so whatever `math` declares has to remain
compatible with the System-level declaration rather than collide with it. That
interaction is the actual work here; see
[[project_builtin_overload_shadows_used_unit]], which is exactly this hazard
(a builtin competing with a used unit's routine of the same name).

Confirm against FPC whether the System-unit result types are `Real`/`Double`
before mirroring them, and check `arctan` spelling (`arctan`, not `atan`).

**Touching `compiler/builtin/**` forces `make stabilize` + `make pin`** — see
[[project_builtin_change_needs_repin_for_gate_fixedpoint]]. Worth batching with
[[bug-pascal-hi-lo-always-split-a-32-bit-value-regardless-of-argument-type]],
found in the same sweep and in the same file, so one repin covers both.

## Gate

A Pascal test diffed against FPC calling each of the six with no uses clause and
comparing formatted output, plus the same program WITH `uses math` (which must
still compile and give the same answers), plus `make test` and the self-host
fixedpoint, then `stabilize` + `pin`.


## Resolved 2026-08-05 — pulled on demand, not redeclared

`sqrt/exp/ln/sin/cos/arctan` now compile with no `uses`, matching FPC:

    writeln(sqrt(16.0):0:1)   ->  4.0     (FPC: 4.0)

**Not** by redeclaring them in builtin. `lib/rtl/math.pas` is 618 lines of
correctly-rounded numerics — `Sqrt` alone carries a Dekker two-product
correction step because plain Newton has an FP fixed point 1 ULP below the
correctly-rounded root. Copying six of those into builtin would recreate exactly
the one-formatter-written-N-times problem the float tickets spent today
collapsing (four hand-written float emitters -> one shim).

So instead the parser pulls the `math` unit **on demand**, reusing the existing
`textfile` mechanism (`needsTextfile` -> `ParseUsesUnit('textfile')`, pulled for
Text/IOResult/Flush). Same guards: skipped under `NoDefaultRtl` and on
xtensa / bare-boot riscv32.

### The scan requires a following '('

The names are short and `ln` is a plausible variable (a line number). A bare
identifier scan would silently pull 35KB of math into any program with
`var ln: Integer`. Requiring `Tokens[i+1].Kind = tkLParen` costs nothing —
these are all functions — and measurably fixes it:

    program with `var ln: Integer` only   ->  procs=93   (unchanged)
    program calling sqrt()               ->  procs=156

### Verified

- all six values byte-identical to FPC;
- an explicit `uses math` still works and still reaches `Power` etc.
  (no double-load);
- a user routine of the same name still binds — and a `var ln` coexists with
  the pulled unit's `Ln`;
- a program using none of the names is unchanged (procs=93).

Test: `test/test_math_intrinsics_no_uses.pas`, which carries both halves —
the five calls and the `ln` variable that must not trigger the pull.

### Caveat found while doing this

An *exact-signature* redeclaration (`function Sqrt(x: Double): Double` in the
program) would now lose to the pulled unit — but that is
[[bug-p-program-function-does-not-shadow-used-unit]], a pre-existing name-
resolution defect this change only makes reachable by a new route. Filed
separately and urgent; not introduced here.

**Resolved:** PENDING-COMMIT

## Log
- 2026-08-05 — resolved, commit PENDING-COMMIT.
