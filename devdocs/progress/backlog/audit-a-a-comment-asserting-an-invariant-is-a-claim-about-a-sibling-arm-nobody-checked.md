
## PASS 1 RESULT: the population has THREE shapes, and proximity does not predict catchability

frankD, 2026-08-29 (`e7385984b`). Population made concrete: **53 hits across 21
files** under `compiler/` and `lib/` for this ticket's own phrase list — small
enough to finish. Pass 1 took the **8 whose claim spans more than one arm**, on
the reasoning that a single-arm assertion has no sibling to betray.

**The distance column was added to test one hypothesis and refuted it.** The
hypothesis (frankA's, and a good one) was: if every instance is close — same file,
same routine, two paragraphs — the problem is *reading what you already have
open*, and the remedy is a review habit rather than tooling.

What came back:

| shape | example | distance | remedy |
| --- | --- | --- | --- |
| **close sibling** | rows 1-7 | same file / same routine | the review habit |
| **self-false** | row 8 (frank-rust) | **eleven lines** | **nothing readable** — only a failing output caught it |
| **distant reference** | frankD's two findings | different files / subsystems | a periodic sweep |

**Proximity does not predict catchability, and the closest instance is the least
reachable by reading.** Row 8's comment is false about its *own* arm and is *more
persuasive than the code beside it* — no sibling to visit, and re-reading would
not have helped. Meanwhile frankD's two are cross-file, where the person reading
the violating code sees nothing wrong **because the claim lives elsewhere**.

So the three columns want **a habit, an oracle, and a sweep**, and only the first
is free. That is a materially different conclusion from the one this ticket was
filed with, and it argues harder against a checker: a checker addresses search,
and search is the failure mode in exactly one of the three columns.

**frankD's own caveat, recorded rather than buried:** pass 1 *deliberately
selected multi-arm claims*, which selects for distance — so its half of the
evidence is biased toward its own conclusion. The single-site "must never" /
"always" assertions are unswept and would likely restore the close-shape
majority. **A survey that names what it selected for is worth several that do
not.**

### Findings filed (neither a live bug)

- **`bug-a-the-ir-frame-op-doc-asserts-a-frame-layout-riscv32-does-not-use`** —
  `defs.inc:816` documents `IR_FRAME`'s saved-fp chain as `[fp]`/`[fp+PtrSize]`,
  universal, no exception. riscv32 is `+8`/`+12`, and `ir.inc:4977` says assuming
  otherwise *"would have silently walked into the locals"*. The lowering asks the
  accessors and is correct; **the IR-op reference a backend implementer reads is a
  false universal** — which is the reader most exposed to it.
- **`bug-a-promocore-is-not-the-only-place-that-knows-the-promo-slot-layout`** —
  `ir.inc:9399` says both promo store paths go through `promocore.pas`, *"the only
  place that knows the layout"*; x86-64's hand-emitted variant-release blob
  encodes `[rax+8]` at three sites in `ir_codegen.inc`. Offsets agree, nothing is
  broken. **~200 lines from the comment that records what instance #4 cost.**

### Verified HOLDING — recorded so nobody re-checks

pypal's syscall table; pylib's three UTF-8 offset helpers; **`ManagedElemKind`'s
nine doors** — the best-maintained instance found, whose own comment *is* the
record of this defect and where every door now asks it; the `InternKey` /
`dbg_filetable` twin; and instance #4's site, re-checked and still fixed.

### Remaining

45 of 53 first-tier hits; **prior #1 (backend/inline twins) is the highest-yield
seam left** — pxx-a5's `builtinheap` census is that shape, and so are both of
frankD's findings plus instance #4. Then prior #2 (frontend lowering arms), then
row 7, which needs a different grep (prescriptions read against their own bodies).

Parked in `unfinished/` with a coverage log so continuation is cheap. **No Track A
file lock was held at any point** — read-only, findings filed as tickets, no
source edited — so the `unfinished/`-is-critical-for-A rule does not bite: it
exists because a half-applied compiler change can break the self-host gate, and
this applies none.
