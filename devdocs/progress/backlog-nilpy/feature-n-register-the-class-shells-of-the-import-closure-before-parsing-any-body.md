---
slug: feature-n-register-the-class-shells-of-the-import-closure-before-parsing-any-body
type: feature
track: N
prio: 55
status: open
summary: "NilPy resolves a method on an unannotated receiver against the classes registered SO FAR, so a class in a module imported later is invisible and the call falls back to runtime dispatch with a warning; registering the import closure's class shells before any body is parsed would make the resolution order-independent"
---

## The mechanism

A call `recv.m(...)` on a receiver with no static class is resolved by scanning
`UCls` for a class declaring `m`. That table holds only the classes registered
by the time the BODY is parsed, and a module's body is parsed when its import
statement is reached. So a class declared in a module imported LATER than the
module doing the calling is not a candidate, and cannot be.

The condition that springs it: two classes in two modules, one declaring a
method `m`, one calling `.m()` on an unannotated receiver, with the CALLER's
module imported first and holding no import edge to the callee's module.

Measured 2026-09-20 on lekkerzeilen blocker 03, six variants against CPython
3.14.4 (`(3.0, 0.5)` in every row):

| variant | shape | pxx |
| --- | --- | --- |
| v1 | `__main__` imports traffic then environment | TypeError (see the bug below) |
| v2 | environment imported FIRST | correct |
| v3 | the shadowing field is a float, not a tuple | fails — the axis is the NAME |
| v5 | receiver annotated `env: Environment` | correct |
| v6 | traffic.py imports environment, receiver still unannotated | correct |
| v7 | result to a local instead of back into the field | warns twice, correct |

v6 is the discriminator: the import edge ALONE fixes it, with no annotation and
no change to `__main__`'s order. That is registration order and nothing else.

## Why it is worth doing

The fallback is a warning plus a runtime dispatch, which is correct (v7) but
gives up static dispatch and prints a diagnostic that is true and unactionable —
lekkerzeilen's build log carries 18 of them over `.wind()`, `.current()` and
`.bed_height()`, and an application author cannot act on any of them.

It is also the precondition for the silent wrong value in
`bug-n-a-field-widened-to-variant-is-claimed-as-a-callable-dispatch-field`:
that bug only fires once this scan has found nothing.

## Shape of the work

A shell pass over the import CLOSURE before any body is parsed. A per-module
shell pass already exists (`PyScanLo` and the import prescan are both cited in
pyparser.inc around the class-alias registration); what does not exist is
recursing it across imports before bodies. Unknown whether the module loader can
be split that way without re-entrancy trouble — that is the first thing to
measure, not this ticket's claim.

## What would retire this

A build of lekkerzeilen whose log carries zero `no class declares a method or
callable field` lines with no application-side import added.

## A SECOND CONSUMER, 2026-09-20: this is plausibly a PERFORMANCE ticket, not only a correctness one

Filed above as a correctness and diagnostic-noise ticket. There is a second
consumer, and it may be the larger one.

**Each `no class declares a method or callable field .m() — dispatching on the
receiver at run time` warning marks a call site that LOST STATIC DISPATCH** and
now goes through `pydyn_meth`, an RTTI lookup by name at run time, on every
call. Measured here: the three-module repro warns **3** times without the import
edge and **0** with it, and the values are correct either way. So the warning
count is a direct proxy for how many sites this defect has pushed onto the
dynamic path, and closing this ticket removes them by restoring the static
resolution rather than by silencing anything.

**Why that is worth pricing.** lekkerzeilen-7a measured the demo on 2026-09-20
(`869ef32`, `devdocs/perf/FRAME-RATE-2026-09-20.md`), interleaved runs on
identical source: the region scene is **4.7x slower than CPython** (2.21/2.37
fps against 10.53/11.49) while open water — same binary, same build, far less of
the demo's own Python per frame — is only **1.19x** (14.62/14.63/14.67 against
17.36/17.34/17.31, spread 0.3% within each arm). The gap scales with how much
application code a frame runs, not with GL, which agrees with the 2026-09-15
finding that the cost is runtime dispatch over the demo's own code. And the 18
warnings in that build are over `.wind()`, `.current()` and `.bed_height()` —
per-frame simulation calls, not startup ones.

**This is a HYPOTHESIS with a cheap test, not a claim, and the test is not "fix
it and see".** Count the surviving warnings in the demo build, then attribute
them: a warning on a path that runs once at startup costs nothing, and one
inside the per-frame sim costs on every frame. If the hot sites are few, this
ticket is a correctness ticket with a small perf tail; if the per-frame calls
are most of them, it is a perf ticket that happens to fix a wrong value. Nobody
has done that attribution and it needs no compiler change.

**One caution for whoever prices it.** The demo currently carries WORKAROUNDS
for this defect (an import edge in `traffic.py`), and the workaround is in the
FASTER direction — it restores static dispatch, as the 3-to-0 measurement above
shows. So 7a's 4.7x was measured with some sites already recovered, and removing
the workarounds after a compiler fix should be neutral-to-faster rather than a
new baseline. Do not read the current number as "what the defect costs".
