---
track: A
prio: 25
type: bug
blocked-by: []
summary: "ir.inc:9399 says a promotable-int store's two paths 'both go through promocore.pas, the only place that knows the layout'. x86-64's hand-emitted variant-release blob in ir_codegen.inc reads the payload as a literal [rax+8] at three sites, so it knows the layout too. The values agree today so nothing is broken — but this is the same arm, the same shape and the same file as instance #4 of the audit, where an x86-64 hand-emitted twin of a 'single choke point' silently diverged for two months."
---

# `promocore.pas` is not the only place that knows the promo/variant slot layout

- **Track A** — `compiler/ir.inc:9399` (the claim), `compiler/ir_codegen.inc:2662`,
  `:2728`, `:3389` (the sibling arm). **No live bug**: the offsets agree.
- Found by the sweep for
  [[audit-a-a-comment-asserting-an-invariant-is-a-claim-about-a-sibling-arm-nobody-checked]].

## The claim

`ir.inc:9399`, on the promotable-int store:

> A promo source is COPIED (which retains its managed heap payload); an ordinary
> integer source is boxed. **Both go through promocore.pas, the only place that
> knows the layout.**

`promocore.pas:62` states the layout it owns: *"A VARIANT slot is 8-byte tag +
8-byte payload on EVERY target."*

## The sibling that also knows it

x86-64 does not call into promocore for variant slot release — it reaches a
hand-emitted blob in `ir_codegen.inc` which compares the tag against
`VT_PROMO_BASE` / `VT_PROMO_LAST` and then loads the payload as a **literal
`[rax+8]`** (`mov rax, [rax+8]`), at three sites. That is the 8-byte-tag layout,
encoded a second time, in machine-code bytes rather than in Pascal.

So the claim is false as written. Nothing is *wrong* today — `+8` is correct and
promocore says the layout is uniform across targets — which is exactly why this
is a latent finding rather than a bug report.

## Why it is worth filing anyway

**This is instance #4 again, in the same file, on the same arm.** That instance
was: `PXXStrUnique` calls itself *"the single choke point for byte mutation,
which is what makes the cache sound"*; it is that on five targets, and **was
never that on x86-64**, which reaches a hand-emitted blob instead — and returned
a writable buffer still advertising a stale ASCII flag for two months
(`regression-test-core-test-nilpy-str-ascii-cache`). The fix is ~200 lines above
these three sites, in `ir_codegen.inc`.

The pattern the audit is chasing is precisely *a "single place" claim whose
exception is x86-64's hand-emitted path*. Here the claim and the exception are
both already in the tree, and the only thing keeping it harmless is that a
constant happens to match. A change to the promo slot layout would be made in
promocore.pas — the place the comment says owns it — and these three blobs would
not move.

## Fix

Two options, and the cheap one may be right:

1. **Correct the claim** (comment-only): say promocore owns the layout *for every
   target except x86-64's hand-emitted variant-release blob, which encodes the
   +8 payload offset directly*, and cross-reference it — so the next layout
   change has a named second site instead of a silent one. Mirrors how the
   `PXXStrUnique` comment now reads after instance #4.
2. **Remove the duplication** by having the blob take the offset from the same
   constant promocore uses, if the emitter can reach it.

Option 1 is honest and immediate; option 2 is the real fix and is a judgement
call for whoever owns the emitter.

## Gate

Track A's usual: `make compiler/pascal26` (fixedpoint) plus, if the blob is
touched at all, a variant/promo repro on x86-64.
