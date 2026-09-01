---
slug: bug-a-riscv32-and-xtensa-still-refuse-aggregate-results-via-virtual-and-indirect-calls-under-a-done-ticket
track: A+S
prio: 50
type: bug
status: working
created: 2026-09-02
found-by: frankC
owner: frankC
blocked-by: []
summary: "riscv32 and xtensa still Error() on an aggregate/frozen-string result returned via a VIRTUAL or INDIRECT call, and the message cites feature-cross-virtual-indirect-hidden-dest — which is in done/. That ticket scoped itself to i386/arm32/aarch64 and those three now implement it; the other two were never in scope and the title says 'cross backends'. Real cost: examples/json/jsondemo.pas builds for i386, arm32 and aarch64 and fails to build for riscv32 and xtensa. Third instance today of a cross-target ticket closing over a subset."
---

# riscv32 and xtensa still refuse aggregate results via virtual/indirect calls, under a ticket marked done

Found by compiling `examples/` across five backends against the x86-64 oracle
(`umbrella-cross-target-codegen-is-correct`, 2026-09-02):

```
jsondemo | i386:ok arm32:ok riscv32:BUILD aarch64:ok xtensa:BUILD
```

Both failures are the same refusal, in `compiler/builtin/pylib.pas`:

```
target riscv32: aggregate/frozen-string result via an indirect call is not yet
supported (feature-cross-virtual-indirect-hidden-dest)
```

Four live `Error()` sites, all still present:

- `ir_codegen_riscv32.inc:3611` (indirect) and `:3808` (virtual)
- `ir_codegen_xtensa.inc:4211` (indirect) and `:4262` (virtual)

and **zero** remaining in `ir_codegen_arm32.inc`, `ir_codegen_aarch64.inc`,
`ir_codegen386.inc`.

## The slug in the message points at `done/`

`devdocs/progress/done/feature-cross-virtual-indirect-hidden-dest.md`,
`status: done`. Read it and it is honest about its scope — *"On i386 / arm32 /
aarch64, a function returning an aggregate ... now errors cleanly"* — it named
three backends and delivered three. Its **title** says "cross backends", and its
error strings are still compiled into the two backends it never covered.

So the instrument that fails here is the SLUG. Someone hitting this error follows
the citation, lands on a ticket marked done, and has to read the whole body to
learn it was about other targets. That is the cheapest possible way to lose a
bug: **the reference is correct about something else.**

## This is the third instance today, and that is the actual finding

Same shape, three times, all found on 2026-09-02:

1. **`bug-a-a-function-returning-a-dynamic-array-is-refused-on-every-cross-target`**
   — title says every, fixed four, left xtensa. Cost: `lib/rtl/sysutils.pas`
   itself would not build for xtensa, so no program using sysutils could target
   the ESP ABI. Fixed `7cc404961`.
2. **the concat-ownership fix** — `ir_codegen_xtensa.inc` records it in its own
   words: *"fixed 'the four cross backends' and never listed xtensa — the
   seventh backend that a grep for the common spelling does not return."*
3. **this one** — three of five, and the two left out are riscv32 and xtensa
   again.

**The population is seven backends** (x86-64, i386, arm32, aarch64, riscv32,
xtensa, wasm32). "Cross backends" is not a number and it keeps being read as
"all of them". Whoever fixes this should also consider whether the enumeration
belongs somewhere a grep can find — a list of backends that a fix must tick off
would have caught all three.

## Why prio 50 rather than 45

A real program (`jsondemo`) is unbuildable on two targets, one of which is the
ESP ABI. It is above ordinary cleanup and below a wrong-value bug, and it should
be wired as a blocker of `umbrella-cross-target-codegen-is-correct` — which had
no blockers at all before this sweep, meaning nobody had attempted the cell.

## Gate

`examples/json/jsondemo.pas` must build and match the x86-64 output on all five
cross targets. Note the existing per-target tests did NOT catch this and could
not have: the same lesson as the dynamic-array ticket, whose regression ran on
x86-64 only.

## Bound

HEAD `d49484b18`, compiler `709ec4626a67`. i386/arm32/aarch64 confirmed by
grepping their emitters for the refusal (0 hits) AND by jsondemo building and
running correctly on all three, which is the second source.
