---
slug: bug-n-type-of-a-member-read-on-a-bare-receiver-jumps-through-a-null-pointer-in-the-lekkerzeilen-demo
type: bug
track: N
prio: 45
status: open
summary: "`type(env.current).__name__` on an unannotated receiver segfaults with PC 0x0 — an indirect call whose callee address was never filled in — in the lekkerzeilen demo, reproducibly (3 of 3, also under setarch -R, also on an older compiler); NOT reduced, and the obvious same-named-field collision has been measured and REFUTED as the cause"
---

# `type(<member>).__name__` on a bare receiver jumps to 0

Reported by lekkerzeilen-7a, blocker 05 (their commit `f638564`), which carries
the demo patch that triggers it. gdb on the demo binary: **PC 0x0 with a clean
return chain** — `Craft.update+0x2f16` <- `Traffic.update+0x13f9` <-
`capture+0xb497` <- `main` — i.e. an indirect call through a pointer that was
never filled in, not a smashed stack.

Reproducible 3 of 3, including under `setarch -R`, so not ASLR, and present on
the older compiler `a6a2a1cc2278e1a9`, so not introduced by tonight's work. It
survives the workaround for
`feature-n-register-the-class-shells-of-the-import-closure-before-parsing-any-body`
(the import edge that fixes the neighbouring `.wind()` call in the same method).

## NOT REDUCED, and one specific cause is REFUTED

7a could not reduce it: two- and three-module reductions of the same shape print
`type is method` and exit 0, with and without the import edge.

**The refuted hypothesis, recorded so it is not re-derived.** The demo has a
textbook instance of this file's neighbouring family — `environment.py:61`
declares `def current(self, x, z)` as a METHOD while `ui.py:1064` has
`self.current = dict(current or {})`, a FIELD of that name in an unrelated
class. That would have made 05 the third door of
`bug-n-a-variant-field-is-claimed-as-the-callee-of-an-open-world-call-...`
(a field claiming a member READ rather than a method call or a property store),
with the hard cast handing back a foreign pointer and `type()` of it jumping to
0 — and it would have explained why a reduction without `ui.py` cannot contain
the bug.

Prediction was written before the run: with the colliding module present the
probe dies or prints garbage; without it, correct. **Measured 2026-09-20: the
three-module program with BOTH declarations present prints `method`, rc=0.**
The collision is not sufficient. What 05 needs is an axis nobody has enumerated,
which is the ordinary state of a minimal case — it fixes every axis you did not
think of, and those are the ones you cannot list.

## How to work it

Not by reducing further. Two independent reductions have now produced the same
false negative. Run candidates against the demo, which is the failing artefact —
mechanism from whoever has the source, verdict from whoever has the failing
tree. The blocker directory holds the patch that triggers it.

## Ranked below its neighbours on purpose

The probe line is 7a's own diagnostic, not demo code. It does not block the
frame, the boat, or any application path. It is a real segfault in a construct a
program may legitimately write, which is why it is filed rather than dropped.
