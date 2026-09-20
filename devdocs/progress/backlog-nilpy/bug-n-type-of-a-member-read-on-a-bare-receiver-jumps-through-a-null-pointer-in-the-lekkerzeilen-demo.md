---
slug: bug-n-type-of-a-member-read-on-a-bare-receiver-jumps-through-a-null-pointer-in-the-lekkerzeilen-demo
type: bug
track: N
prio: 45
status: open
summary: "A BARE READ of a method as a value off an unannotated receiver -- `m = env.current`, no call -- segfaults with PC 0x0 in the lekkerzeilen demo, an indirect call whose callee address was never filled in. THE OPERATOR IS THE READ, NOT type(): the original probe bundled a read, a type() call and an __name__ fetch into one expression, and split into four markers it dies before type() is reached, so the old title and the `no isolated repro` finding were both measured against the wrong operator. Cause UNKNOWN; three candidates are eliminated by measurement -- blocker 03's name collision, ASLR, and the module-scan normalisation bug whose fix clears an identical-looking sibling and does nothing here. Demo-only, one variable."
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


## 2026-09-20, frankb-8e — the operator is the READ, and three causes are eliminated

**Everything below this line supersedes the title and the "NOT REDUCED"
section above, both of which were measured against an operator that is not
involved.**

### The operator

The probe was `type(env.current).__name__` — three operations in one
expression, so a crash anywhere in it reads as the outermost one. Split into
four markers against the real artefact:

```
PROBE A: about to bind the method as a value    <- printed
  _m = env.current                              <- SIGSEGV HERE
PROBE B: bare read survived                     <- never printed
```

**It dies binding the method as a value. `type()` is never reached.** So "two-
and three-module reductions print `type is method`" was reducing the wrong
thing, which is why five sound reductions all passed.

### Eliminated, each by a measurement

| candidate | how it was eliminated |
| --- | --- |
| blocker 03's name collision | 03 is FIXED in the compiler (`fb0c0af11`) and 05 still reproduces with **no workarounds at all**. The ticket's stated precondition is false. |
| ASLR | `setarch -R`, unchanged |
| the module-scan normalisation bug | `a60a8daa0` fixes an identical-looking bare-read segfault and **does nothing here** — `PROBE A` prints, `PROBE B` does not, rc=139 |

**That last row is the valuable one.** `done/bug-n-a-bare-read-of-a-method-as-a-
value-yields-a-garbage-code-address` has the same operator and a 3-file repro,
and it is **NOT this bug**. Its RIP is `0x4004ac` — inside the ELF headers, a
carrier **built wrong**; this one is `0x0`, a carrier **never built**. A fix
clearing one and not the other is the evidence that would have joined them, and
it does not exist. **Do not close this ticket when that one is fixed. It
already is.**

### The repro is now one variable

The demo patch bundles the 03 workaround, the 04 workaround and the probe.
**Both workarounds are dead weight — the compiler fixes landed.** Apply only
the probe to a clean demo tree. Control leg sails, rc=0; probe leg rc=139 with
no probe output; identical flags, one script.

### Ranking note

**This blocks nobody today and the prio is not being raised.** The probe line
is not demo code — it was a diagnostic added while chasing 03 — and the demo
runs without it. It is worth keeping because a segfault where a `TypeError` is
expected is worth more than a workaround, not because anything waits on it.
