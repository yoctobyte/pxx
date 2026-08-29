---
track: A
prio: 55
type: bug
blocked-by: []
summary: "jsondemo and life do not build for aarch64 at all -- 'aggregate result with more than 8 params not supported', raised from builtin/pylib.pas, so it fires for any program pulling that unit in. The sharp part is not the two programs: it silently narrows the corpus available for BEHAVIOURAL verification on aarch64, while census tables built from target-independent IR keep listing those same programs as aarch64 data points. Two purposes, one list, only one of them ever checked."
---

# aarch64: an aggregate result with more than 8 params is unsupported, and it takes two corpus programs with it

- **Type:** bug — **Track A** (aarch64 backend / ABI, `compiler/**`). Obeys A's
  gate.
- **Found:** 2026-08-29, while verifying
  [[feature-opt-emitloadvara64-needs-a-destination-register-parameter]]. Not
  caused by that work — it reproduces on `pinned` and on every binary tried.

## The failure

```
$ pxx --target=aarch64 -O2 examples/json/jsondemo.pas /tmp/jd.a64
pascal26:14721: error: target aarch64: aggregate result with more than 8 params not supported
  in: /home/neo/frank-optimize/compiler/builtin/pylib.pas
  near: end  end  end  >>> end  function
```

Same for `examples/life/life.pas`. Both fail at **-O0, -O2 and -O3 alike**, so it
is not an optimisation interaction. The error is raised from `pylib.pas`, not
from the user program, so it fires for anything that pulls that unit in — the two
programs found are the ones that happen to be in the example tree, not the
population.

## What it actually costs — and this is the part worth filing

Not "two demos don't build". The cost is that **one program list is serving two
different purposes and only one of them was ever checked.**

A census like the one in `feature-opt-emitloadvara64-*` counts **target-
independent IR shapes** — how many binops have a constant right operand, a
leaf-sym right operand, and so on. That count is produced by the frontend and the
shared IR, so it is valid for aarch64 whether or not aarch64 can emit the
program. **The census is not wrong.**

What does not follow is that the same list is available for **behavioural**
verification on that target. That needs the program to build *and* run, and
`jsondemo` cannot do either on aarch64. So a table reading

> measured across `compiler.pas`, mandelbrot, chess and jsondemo

is accurate about what was counted and quietly misleading about what could be
*tested* — chess does not build for aarch64 either (stackful generator, x86-64
only), and now jsondemo does not. Two of the four named programs are
census-only, and nothing in the table says so.

The failure mode is not a wrong number. It is a **verification corpus that
shrinks without announcing it**: a differential harness over "the usual
programs" compiles what it can, skips what it cannot, and reports success over
whatever survived. The harness used for the ticket above did exactly that until
it was hardened to report skips — its first negative-control run silently
skipped 3 of 6 pairs.

## Why it stayed invisible

Nothing routinely builds these examples for aarch64. Cross-target sweeps run the
`test/` suite, not `examples/**`, and the aarch64 shard's greens are therefore
consistent with two example programs having never compiled for that target at
all.

## What to do

1. **Fix the backend limit.** An aggregate result past 8 parameters is an ABI
   lowering gap on aarch64, not a language restriction — the other targets
   manage it. That is the actual bug.
2. **Separately, and cheaply: make the shrinkage loud.** Any harness that
   compiles a corpus per target should report what it *skipped*, not just what it
   compared. A count of comparisons is not a count of coverage, and the two look
   identical in a green report.

## Also seen, same session, unrelated cause

`test/test_a64_leafsym_binops.pas` does not build for **arm32/riscv32**:
`{$Q+}: PXXOverflow runtime helper not found (builtinheap not loaded)`, raised
from `builtin/softfloat.pas`. Pre-existing, independent of the aarch64 error
above, and recorded here only so it is not re-discovered as new. Split it out if
someone takes it.

## Gate

A's gate (`make compiler/pascal26` + self-host fixedpoint). Plus, for the fix:
`jsondemo` and `life` build for aarch64 and their qemu output matches the
x86-64 oracle — which is the point of fixing it, since it is corpus that
verification gets back.
