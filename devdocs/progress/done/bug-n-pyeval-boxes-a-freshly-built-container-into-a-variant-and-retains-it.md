---
type: bug
track: N
prio: 60
status: open
slug: bug-n-pyeval-boxes-a-freshly-built-container-into-a-variant-and-retains-it
---

# pyeval boxes a FRESHLY BUILT container into a variant and then retains it

Nine sites in `compiler/builtin/pyeval.pas` build an object, write its handle
raw into a variant slot (`VType := 7; Payload := ...`) and then call
`PXXObjRetain` on it. Every one carries the same comment -- *"slot owns +1
(magic-guarded)"* -- and the comment is right about the SLOT and wrong about
where the +1 comes from: the object was just constructed and already carries
rc=1, so the retain makes it rc=2 against the single release the slot's clear
performs. Net +1 per evaluation, forever.

This is the SAME SHAPE as five defects already fixed on 2026-09-14
(`17462f54e` -- the four eager pair builders and `TPyDict.itemlist`; `17e5731a7`
-- the cursor's own FBox; `bug-n-a-user-operator-on-a-variant-operand-leaks-its-result`
-- `PyUserArithCall1`). The discriminator in every case is one question:

> is the object the retain is applied to BORROWED from somewhere that keeps its
> own reference, or was it CONSTRUCTED on the line above?

A borrowed one needs the retain. A constructed one does not, and the retain is
the leak.

## THE SITES, NOT YET INDIVIDUALLY MEASURED

| file:line | object | constructed on the spot? |
|---|---|---|
| pyeval.pas:3477 | `li` list literal | yes -- `TPyList.Create` above |
| pyeval.pas:3489 | `dd` dict literal | yes -- `TPyDict.Create` |
| pyeval.pas:3508 | `dd` dict literal | yes |
| pyeval.pas:3522 | `li` set literal | yes |
| pyeval.pas:3565 | `li` tuple literal | yes |
| pyeval.pas:3949 | `r` range result | yes |
| pyeval.pas:4347 | `gres` | probably |
| pyeval.pas:4387 | `by` from `pyint_to_bytes` | fresh call result |
| pyeval.pas:4442 | `b2` from `pystr_encode` | fresh call result |
| pyeval.pas:600 / 1243 / 1399 / 1482 | host-call results / field reads | MIXED -- 1482 is documented as a field READ, which genuinely borrows |

`pylib.pas:14205` (`cur := pyiter_v(...)`) belongs to the same question and is
not settled either.

**Do not bulk-remove these.** `pylib.pas:5476`, `18075` and `PyObjAsVar`
(`20608`) look identical and are CORRECT -- their object is the caller's, and
removing the retain there hands back a net release of a live object. That was
measured once already and the note above `PyObjAsVar` records the SIGSEGV.
Each site needs its own answer to the question above.

## WHY THIS IS NOT PRIO 85

`pyeval` is the interpreted `eval()`/`exec()` path. It is not on the frame path
of any demo we currently run, and the leaks that were 95% of lekkerzeilen's
histogram are elsewhere and fixed. Real, mechanical, and worth a session --
just not ahead of anything a running program touches.

## HOW TO MEASURE ONE

`-dPXX_OBJTRACE`, a loop of N evaluations, count allocations with no matching
`F`. **Assert the trace is NON-EMPTY before counting** -- an empty trace makes
"unmatched allocations" report zero, which reads exactly like a clean result.
That cost a wrong conclusion on 2026-09-14 (a pinned-compiler control invoked
without the flag reported the fix had CAUSED the leak).
