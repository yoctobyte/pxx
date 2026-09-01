---
slug: bug-o-nothing-asserts-that-o2-actually-uses-the-static-literal-handle
track: A
prio: 35
type: bug
blocked-by: []
status: backlog
found: 2026-09-02
found-by: frankC
owner: unassigned
summary: "`EmitStaticLitHandle` (compiler/ir_codegen.inc, gated `OptLevel < 2`) turns a string literal into an address into the image instead of a PXXStrFromLit call that allocates and copies — worth 9.28% of uforth's profile in PXXStrFromLit alone and most of another 19% in the allocator around it. If the pass silently stopped firing, EVERY test would still pass: the literal would become an ordinary refcounted heap copy, which is what -O0/-O1 already produce and what the whole suite already accepts. The optimisation has no guard, only its correctness does."
---

# Nothing asserts that -O2 actually uses the static literal handle

Found while resolving
[[bug-a-a-refcount-test-passes-at-o2-and-fails-at-o0-and-o1]], which was the
same pass seen from the other side: a test asserted the -O2 representation
unconditionally and failed below the gate. Fixing it meant making the suite
accept BOTH representations at every level — which is correct, and which is
exactly what leaves this hole.

## The hole

`EmitStaticLitHandle` opens `if OptLevel < 2 then Exit`. Above the gate a
literal IS the ready-made managed block in the image; below it the literal
reaches `PXXStrFromLit`, which allocates and copies the same bytes on every
evaluation. Measured at `480d4584403c`:

```
        meta   static-flag   pointer            rc born
-O0     5120   FALSE         mmap region                 1
-O2     5376   TRUE          inside the image   1073741824
```

Both are CORRECT — that is the point. So if the pass regressed to never firing,
`-O2` would produce the `-O0` column, every row of every test would still pass,
and the only symptom would be that uforth got slower by the margin the pass was
built for. A performance pass whose absence is invisible to the suite.

This is not the same as
[[feature-opt-static-literal-blocks-should-never-be-written-to]], which is about
whether a static block is ever WRITTEN. That one guards the block's integrity
once it is used. This one is about whether it is used at all.

## What would fix it

An assertion that the representation matches the LEVEL, which needs the program
to know its own `-O` — the test cannot see it today, which is why the resolved
ticket branched on the runtime meta flag instead. Two shapes worth weighing:

1. **A predefined symbol** (`{$ifdef PXX_OPT_LEVEL_2}` or similar) so a test can
   say "at this level the literal MUST be static". Cheap to consume, and it
   makes the -O level a thing source can reason about, which nothing else needs
   yet — so it is a language surface decision, not just a flag.
2. **An emit-side count**, in the shape the Makefile's MOVSP row already uses:
   compile a program with N literals at -O0 and at -O2 and assert the
   `PXXStrFromLit` call count is N and 0. This needs no language surface and
   reads the thing that actually regressed. Probably the right one.

Shape 2 also generalises: the same harness would catch any -O2 pass that
silently stops firing, which is a class this repo has no coverage for at all.
Rate it on that rather than on this one pass.

## Why prio 35 and not higher

It cannot produce a wrong answer — both representations are correct, so the
worst case is slow, not incorrect. It ranks above the usual perf-guard work
only because the pass it protects has a measured 9.28%+ number attached and
because the generalisation in shape 2 is worth more than this instance.
