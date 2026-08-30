---
track: A
prio: 55
type: bug
blocked-by: []
summary: "jsondemo and life do not build for aarch64 at all -- 'aggregate result with more than 8 params not supported', raised from builtin/pylib.pas, so it fires for any program pulling that unit in. The sharp part is not the two programs: it silently narrows the corpus available for BEHAVIOURAL verification on aarch64, while census tables built from target-independent IR keep listing those same programs as aarch64 data points. Two purposes, one list, only one of them ever checked."
status: done
owner: frankA
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

---

## RESOLVED 2026-08-30 (frankA, Track A) — two defects, and the second one was silent

**Verified still broken at HEAD before any work** (`bfd6e7f0e`, self-hosted
`644519c0244e`): `jsondemo` for aarch64 still raised
`aggregate result with more than 8 params not supported`. `examples/life/life.pas`
could not be used as the second witness — on this host it fails earlier and for
an unrelated reason (`C include file not found: "gtk/gtk.h"`), so the ticket's
"same for life" claim is neither confirmed nor refuted here.

### Reduced to 14 lines

```pascal
type TBig = record a, b, c, d: Int64; end;
function Make(p1, p2, p3, p4, p5, p6, p7, p8, p9: Int64): TBig;
```

Nine parameters — one past the eight that fit in `x0..x7` — returning an
aggregate. That is the whole trigger; `pylib.pas` was incidental.

### The visible defect

`compiler/ir_codegen_aarch64.inc:3115`. AAPCS64 passes the indirect result
location in **x8**. The `<= 8` argument arm gets it by popping one slot past the
args (`ldr x8, [sp], #16`); the `> 8` arm reads its temps by OFFSET instead of
popping, and nobody wrote the corresponding `ldr x8`, so it raised an `Error`
rather than emitting the call.

**It was never a lowering difficulty.** The hidden-destination slot was already
being pushed at the top of the case, before the argument loop — the old `Error`
fired *after* that push. What was missing was one load and the 16 bytes below.

### The second defect, which is why this took a loop to verify

The post-call cleanup did not account for the hidden-destination temp. It is one
more 16-byte slot than the arguments, and `add sp, sp, #(hi + nArgs*16)` restores
sp to the slot rather than past it.

**That does not fault. It leaks 16 bytes of stack per call and returns the
correct answer.** A single call is perfect. So is a thousand.

**My first regression test was too small and PASSED against a deliberately
broken compiler.** 200000 iterations leaks 3.2 MiB, which fits inside a default
8 MiB stack. Removing the `+ 16` from the cleanup, rebuilding, and running it
gave the right answer and exit 0 — a test that could not fail, written to guard
the exact defect it could not see. Sizing it properly: 8 MiB / 16 bytes = 524288
calls to exhaust the stack, so the test uses **2000000** (~32 MiB, 4x margin),
measured to **segfault the broken build** (`qemu: uncaught target signal 11`)
and pass the fixed one.

That is the same error as this ticket's own subject, one level up: a corpus that
shrinks without announcing it, and a test whose coverage is smaller than it
looks. Both report success over whatever survived.

### Gate

- `make compiler/pascal26` — converged, 1 round, `8444cdce006a`.
- **The ticket's stated gate:** `examples/json/jsondemo.pas` builds for aarch64
  at `-O2` and its qemu output is **identical to the x86-64 oracle**, 27 lines,
  compared whole rather than sampled.
- The 14-line repro agrees with the oracle (`10 10 10 15`) on both targets.
- All five targets agree on the 2M-call program: x86-64, i386, aarch64, arm32,
  riscv32 all print `sum=2000019000000 last=2000009 10 10 15`.
- **Byte-identity 15/15**, three programs × five backends, baseline
  `644519c0244e` vs fix `8444cdce006a` — *both built at this one HEAD*. The
  first attempt at this comparison reused a baseline emitted before an
  intervening `git pull`, reported 15/15 DIFFERENT, and was measuring other
  people's commits. Rebuilt under a stash, and note that a `stash pop` restores
  sources and not binaries, so the second arm was rebuilt too.

### Regression test

`test/test_aggregate_result_over8_params.pas`, wired into `test-core` natively
and on aarch64. Native is the oracle; aarch64 is the target that was broken. The
other three run this shape correctly and were verified once at fix time — they
cost ~13s of qemu per run to re-confirm a path this change never touched, which
is why they are not in the row rather than an oversight.

This closes the ticket's own observation that *"cross-target sweeps run the
`test/` suite, not `examples/**`"*: the shape now lives where the sweeps look,
instead of only in an example that silently stopped building.

### What is NOT fixed, deliberately

**"What to do" item 2 — make the corpus shrinkage loud.** *"Any harness that
compiles a corpus per target should report what it skipped, not just what it
compared."* That is real and it is not mine: those harnesses are `tools/**`,
Track T's file-lane. Filed nothing new because the specific harness this ticket
names was already hardened to report skips; if a second one is found, it is a T
ticket, not a reopening of this one.

**The `life.pas` half** is unverified here for lack of GTK headers on this host.
The aggregate-result error it shared with `jsondemo` is fixed; whether `life`
then builds is untested.

### Split out

The ticket's *"Also seen, same session, unrelated cause"* section — `{$Q+}`
failing on arm32/riscv32 with `PXXOverflow runtime helper not found` — still
reproduces at HEAD and is now
[[bug-a-q-plus-overflow-checking-has-no-runtime-helper-on-arm32-and-riscv32]],
as this ticket asked. It shares nothing with the aggregate-result bug but the
session that found it, and leaving it here would have closed a ticket that still
contained a live defect.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
