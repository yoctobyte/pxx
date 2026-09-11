---
track: P
prio: 55
type: feature
owner: frankS
blocked-by: []
summary: "DONE 2026-09-11: `Initialize(x, n)` / `Finalize(x, n)` — the element-count form, x being the first of n consecutive elements — was a DELIBERATE refusal in feature-a-implement-initialize-and-finalize-over-the-arc-helpers and is now implemented: parser carries the count on ASTRight[AN_MANAGED_INIT], ir.inc lowers to new builtins PXXRecordInitializeN/PXXRecordFinalizeN with RecSize as the stride, non-record element types get a recovering diagnostic. It was the last wall between pxx and FPC's cclasses.pas, which now compiles."
status: done
---

# The element-count form of `Initialize` / `Finalize`

`Initialize(x, n)` and `Finalize(x, n)` treat `x` as the **first of n consecutive
elements**. FPC's own RTL spells both that way wherever the count is not a
compile-time constant, so the form is not an edge case — it is how a container
finalizes its storage.

**It was refused on purpose**, and the refusal is recorded in
[[feature-a-implement-initialize-and-finalize-over-the-arc-helpers]]: *"Accepting
and ignoring it would put the silent no-op straight back, in the one shape that
leaks an array's worth of references instead of one."* That reasoning was right
about ignoring it. This ticket implements it instead.

## What was built

- `compiler/builtin/builtinheap.pas` — `PXXRecordInitializeN` / `PXXRecordFinalizeN`,
  a loop over the existing one-element helpers, taking `count` and `elemSize`.
  A non-positive count is a documented **no-op**, because FPC's callers reach it
  with a freshly-emptied container (`Finalize(FItems^, FCount)` right after
  `FCount` became 0).
- `compiler/pasparser_stmt.inc` — the optional second argument, carried on
  `ASTRight[AN_MANAGED_INIT]`, `-1` for the one-element form. The string-desugar
  arm reads `miArgTk`, captured **before** the count expression is parsed —
  `LastExprTk` is the LAST expression parsed and this arm asks about the FIRST.
- `compiler/ir.inc` — lowers the count form to the N-helper. A non-record element
  type with a count gets `ErrorAtRecover`, not silence.

## THE STRIDE IS PASSED IN AND IS NOT IN THE DESCRIPTOR

The layout descriptor these lower onto enumerates a record's **managed members**
and carries no size, so a step derived from it walks 16 bytes where the fixture's
`TRec` is 24 — an unmanaged member wedged between two managed ones contributes to
the stride and appears nowhere in the descriptor. `RecSize(rec)` is passed as a
fourth argument for exactly that reason.

**Measured, not reasoned:** build with the descriptor-shaped guess `16` in place
of `RecSize` and the fixture SIGSEGVs (rc=139) after printing its first row.

## Why it mattered: the wall, and what it is NOT worth

This was the wall FPC's `cclasses.pas` was sitting behind — two reported errors
in that unit, at lines 1726 and 1893, and **both were this**. With it in,
`cclasses.pas` compiles: `ok: [code=536232B data=109348B bss=93392B procs=1487]`.

**Do not price this at "150 units."** The FPC-corpus umbrella's BOTH-OK count has
been 15 for four consecutive runs, and four null rows in a row say that 150 is a
QUEUE POSITION, not a blocked population — the units behind cclasses.pas have
never been compiled far enough to know what they hit. The honest claim is one
unit, measured, plus whatever the next corpus run reports.

## Test

`test/test_p_the_element_count_form_of_initialize_and_finalize.pas`, wired into
the `Makefile` beside `test_fwdptrparam26`. Every expected line is fpc 3.2.2's
for the identical source. Three controls, all run:

1. **Initialize** — delete the `Initialize(p^, 3)` line and the identical program
   is `Runtime error 216` under fpc and SIGSEGV under pxx. `GetMem` +
   `FillChar($FF)` is what makes that true; a stack array is already zero and the
   control could not fire.
2. **Feature** — the PINNED compiler refuses the file at line 80 with the old
   `element-count form is not implemented`. A control for the feature, **not** for
   the stride: it stops in the parser and never reaches the lowering.
3. **Stride** — the wrong-stride build above.

Rows assert the middle of the array (`a[1], 2`), so an off-by-one at either end
moves a row; idempotence (`again`); the zero count (`zero`); a one count (`one`);
and `keep`, which holds a copy taken before the Finalize — Finalize drops a
REFERENCE, so the copy must stay valid.

## Log

- 2026-09-11 frankS — implemented and landed, commit d095cb08d. Filed and closed
  in the same commit: the work was done before the ticket existed, because
  frankH deliberately left it unfiled so it would land in this seat's step 3
  rather than collide with it.
