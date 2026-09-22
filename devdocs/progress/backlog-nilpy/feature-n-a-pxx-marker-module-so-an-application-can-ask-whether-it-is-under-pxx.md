---
slug: feature-n-a-pxx-marker-module-so-an-application-can-ask-whether-it-is-under-pxx
title: a pxx marker module, so an application can ask whether it is under pxx
summary: "**DECIDED AND UNBUILT, WHICH MAKES THIS THE CHEAPEST KIND OF LOOSE TIE UNDER THE 2026-09-22 OWNER PIVOT (`wrap up all loose ties`). THERE IS NO DECISION LEFT IN IT.** The owner settled the spelling on 2026-09-20 -- a DUNDER, `__pxx__`, chosen so that nobody can publish a PyPI package that makes the check come out true under CPython. MEASURED 2026-09-22 by frankz-e5: `__pxx__` has ZERO references in `compiler/` and ZERO in `lib/`, so none of it exists. RELAYED AND NOT VERIFIED BY ME: frankuser reports it unblocks 10 of tuxspaceprogram's 20 remaining failures, and lekkerzeilen with a small app-side change. I have not established what that 20 enumerates, when it was taken, or against which tree -- so treat it as a pointer to go measure, not as a number to quote. DELIBERATELY NOT RE-RANKED ON THAT COUNT: CLAUDE.md says not to rank a blocker on how many subjects name it, and a first-failure census ranks by queue position. The argument for doing this is that it is SETTLED and UNBUILT under a pivot that asked for loose ties to be closed, which is a goal-alignment argument and not a headcount. NOTE THE EDGE SET IS EMPTY AND NOTHING IN the backlog CITES THIS TICKET, so whatever it unblocks is invisible to `effective_prio`; if a seat confirms the TSP rows, wire the edges rather than raising this number by hand. OWNER'S DECISION 2026-09-20 (relayed by frankuser, secondhand): instead of an application detecting pxx by `try: import ctypes` FAILING, give pxx a special named module that exists ONLY under pxx, so the application asks the question directly. His words: *\"we could have PXX have a special named module (could be mostly empty) that would indicate if we are compiling under pxx. that way, we don't need the 'ctypes import' hack - and can safely implement a ctypes. small change in the lekkerzeilen and TSP application, and allows us to move forward.\"* The mechanism already exists and needs no new machinery: NilPy resolves `try: import X / except ImportError:` at COMPILE time, and CPython takes the except arm naturally because the module is not there. **BUYS ZERO UNITS TODAY AND THIS FIELD LED WITH A COUNT OF 10 UNTIL 2026-09-21.** The count was true of a PREDICTED mechanism and the measurement went the other way, so the field acquired a dependency on the prediction holding; reported by frankz-e5 off tsp-compile-wall-inventory-2026-09-20.md's re-sweep, and re-verified here in TSP's own source rather than on report. THE MECHANISM, WHICH DOES NOT DECAY: the marker is NECESSARY for the pxx arm and NOT SUFFICIENT while `_pxx_backend.py` is absent. tsp/platform/__init__.py:98-109 is `try: import __pxx__ / except ImportError: _ctypes_backend / else: from . import _pxx_backend` -- so shipping the marker makes pxx take the ELSE arm and fail one line later on a module that does not exist (`find _pxx*` over the whole archive returns nothing). The wall moves; it does not clear. Same for lekkerzeilen, where the actual unblocker was the NESTED-GUARD bug, fixed separately, and the marker is a SIMPLIFICATION its seat can live without. WHAT WOULD RAISE THIS AGAIN: the parked ~1k-line `_pxx_backend` port landing, which is the owner's to unpark (tuxspaceprogram-c6, twice) and is not a ticket in this repo. PRIO DROPPED 80 -> 45 FOR THAT REASON: at 80 it was the top of the TSP queue and a seat pulling `ready --track N` was being sent to work that clears nothing. For TSP: `_pxx_backend` DOES NOT EXIST, so shipping the marker moves TSP from failing at `ctypes` to failing at `_pxx_backend not found` -- the real gate is a parked ~1k-line port and it is the owner's to unpark (tuxspaceprogram-c6, twice). For lekkerzeilen: the unblocker was the NESTED-GUARD bug, fixed separately, and the marker is a SIMPLIFICATION its seat can live without. So this ticket is WITHOUT pxx pretending ctypes is absent -- and it leaves room to implement a real ctypes later. TWO ENGINEERING POINTS ARE OPEN, both raised to the owner and neither settled: the module's NAME (a claimable name like `pxx` answers TRUE under CPython for anyone who pip-installs a package of that name; a dunder-ish name such as `__pxx__` cannot be claimed -- and `sys.implementation.name` is where a CPython programmer looks first, with the module as the cheap check), and its CONTENT (he said \"mostly empty\"; a seat proposed target, pointer size and version, since applications have no way to ask today -- last week's `sys.maxsize` bug was that same gap). **THE NAME IS `__pxx__` -- HIS RULING, RELAYED, NOT HEARD FIRSTHAND BY THIS FIELD'S AUTHOR, 2026-09-20.** The word RELAYED is inside the sentence a re-teller would quote, deliberately: on this exact question a headline has already detached from its body once today. Provenance in full, because provenance is what went wrong here once: relayed by frankuser, which reports **three separate turns in his own pane** -- he chose `__pxx__` from options it put to him with that exact spelling shown; then, unprompted, *"good. that's decided then. tell TSP the same"*; then *"yes"* to telling the lekkerzeilen seat; and finally, when the question kept being relayed, *"i already said __pxx__ is just fine, 3 times now."* **THE EARLIER RETRACTION IN THIS FIELD WAS CORRECT WHEN MADE AND IS NOW COMPLETED, NOT CONTRADICTED.** The first answer came off a seat's menu, which is exactly the shape a second source exists to catch; what was wrong afterwards is that the doubt outlived its own refutation -- he re-confirmed twice in his own words while the question went on being relayed. **The PROPERTY he was answering is unchanged and is the reason the spelling is right: a third party must not be able to make the check come out TRUE on ordinary CPython by publishing a package of that name, so the spelling must be unclaimable.** Anyone re-opening this should read his own pane, not this field. **AND THE DETECTION IS LEXICAL, NOT A BOOLEAN**: a module-level `HAVE_PXX = True/False` tested elsewhere is a RUNTIME condition and pxx compiles the ctypes arm anyway, defeating the whole mechanism -- the guarded import sits where the choice is made, with the selected name bound on both arms (worked example: TSP `98e9e66`). **RELATED AND POSSIBLY ONE FIX: `devdocs/pxx-blockers/07-nested-import-guard-compiles-the-dead-arm/` (lekkerzeilen-7a, `5a7fc43`) -- a FLAT import guard is correctly skipped and a NESTED one is COMPILED, so the only shape that works on both today's compiler and one that ships this module is refused today.** Whoever takes this should have 07 in hand."
track: N
type: feature
prio: 45
status: backlog
owner: ""
blocked-by: []
---

# A pxx marker module

## Why this shape and not a ctypes shim

The hazard the owner's inversion removes, measured 2026-09-19 and recorded in
`devdocs/dev/resume-after-reboot-2026-09-19.md`: both lekkerzeilen and TSP select
their backend with `try: import ctypes / except ImportError: _pxx`, which NilPy
resolves at COMPILE time. **The moment an importable `mimic_ctypes` exists, both
applications flip onto the CPython arm silently**, because the import SUCCEEDING is
the signal. That is why a partial ctypes is worse than none.

Asking the question directly inverts it: the application tests for pxx, not for the
absence of ctypes, so implementing ctypes later cannot flip anything.

## What is measured and what is not

- **Measured**: NilPy resolves a guarded import at compile time (the mechanism this
  relies on) — same mechanism recorded in the hazard above.
- **Measured**: 10 of TSP's 20 remaining compile failures are ctypes-gated
  (`0dfa0d78d` census, frankh-c0; unchanged at `45b8571d7`).
- **Measured 2026-09-20, and it is the row that decides this ticket's value**:
  `ls /home/neo/tuxspaceprogram/tsp/platform/` is `__init__.py`,
  `_ctypes_backend.py`, `_gl.py`, `_sdl2.py`, `_vocab.py` — **there is no
  `_pxx_backend.py`**, and `__init__.py:107` is `from . import _pxx_backend as
  _backend`. So shipping the marker moves TSP's wall from `ctypes` to
  `_pxx_backend not found`, one line earlier in the same file, and **delivers
  zero compiling units**. It is still worth building (lekkerzeilen wants it, and
  it is what lets a real ctypes ship later) — it is not a TSP unblocker, and the
  ctypes-gated 10 above must not be read as its yield.
  Full board: `devdocs/dev/tsp-compile-wall-inventory-2026-09-20.md`.
- **NOT measured**: whether the guarded-import arm selection binds correctly when the
  live arm is lexically FIRST. CLAUDE.md records a first-wins alias-table defect of
  exactly this shape (`uses`/import order). **Whoever takes this must write the
  fixture with the marker import in BOTH positions**, and with and without an `else:`.

## Open, for the owner

1. **Name.** `pxx` is claimable on PyPI; `__pxx__` is not. Also consider
   `sys.implementation.name`, which is the first place a CPython programmer looks.
2. **Content.** "Mostly empty" versus carrying target, pointer size and version.

## Not pxx's to change

The application-side edits in lekkerzeilen and TSP belong to those repos' seats.

## ADDENDUM 2026-09-20 — the superglobal variant, and why the import wins

The owner offered a simpler shape and then settled it himself (relayed by
frankuser, secondhand): *"it could even be simpler by having pxx define a
'superglobal' that we could just test.. (so just - if __HAS_PXX is not none: )..
but the import hack is fine too, just make the name a bit more magic (dunders, or
some other special chars)"*.

**The import idiom with a dunder-ish name is the shape to build.** A bare
superglobal is NOT symmetric: under CPython an undefined name raises `NameError`
rather than evaluating to None, so `if __HAS_PXX is not None:` CRASHES there and the
application needs a `try/except NameError` anyway — uglier than the import, and
linters and type checkers flag the undefined name besides.
`if globals().get('__PXX__'):` would work on both sides, **but that depends on NilPy
supporting `globals()`, which is UNVERIFIED — do not quote it as available without
measuring it.**

**SETTLED 2026-09-20: the spelling is `__pxx__`, his ruling.** ~~The exact
spelling is still the owner's. He asked for dunders or other special characters;
`__pxx__` was a seat's suggestion, not his instruction.~~ Struck rather than
deleted: that was TRUE when written and it is the reasoning that correctly sent
the question back to him. He then confirmed the spelling three times in his own
words (see the summary for the turns).

**The property that makes this cheap on the application side, and the reason he
likes it:** pxx resolves the import at COMPILE time, so the CPython arm is never
compiled. The application keeps its ctypes code exactly where it is and **pxx does
not need to understand any of it.**

## ADDENDUM 2026-09-20 — the three measurements, and the ticket is UNOWNED on purpose

Measured by frankh (Track N) with no change to the tree; each is a compile of a
probe against the HEAD compiler, and each answers a question this ticket had
open. Nobody holds this ticket; these are here so whoever takes it starts from
measurements rather than from the two predictions they replace.

**1. The dead arm really is not compiled, and the bar was set deliberately
high.** The probe's `except ImportError:` arm held `import ctypes` AND an
expression the compiler cannot type at all. Neither reached the compiler: the
build is clean and the binary runs. So the mechanism this whole ticket rests on
is confirmed at the strength the application needs — the CPython arm may contain
anything, and pxx does not need to understand a line of it.

**DO NOT LIFT THAT CONSTRUCTION INTO A DIFFERENTIAL TEST. It is right here and
it is a guard that cannot fail there.** Raised by tuxspaceprogram-c6 and
frankb-8e, 2026-09-20, and recorded beside the measurement rather than left in a
message, because the probe is the part someone will copy. For THIS proof —
*the dead arm is not compiled* — untypable `ctypes` code is arguably the
sharpest possible filling, since code the compiler cannot type either errors or
proves it was never reached. In a probe that compares pxx against a CPython
ORACLE it is the opposite: CPython RESOLVES `ctypes` and pxx does not, so the
two run DIFFERENT ARMS and the comparison can never fail, whatever is wrong.
Same construction, one use sound and one certifying nothing.

Worth knowing why it was loud, because it is the same property from the other
side: `ctypes` in a dead arm is exactly what made lekkerzeilen's blocker 07
LOUD while the identical defect stayed SILENT elsewhere. frankb-8e fixed 07 the
same day — the import pre-scan tracked one `try` by depth rather than position —
and found the ordinary case is silent: the excluded module resolves quietly,
**its top-level code RUNS**, and member reads come off the dead arm with exit 0
and no diagnostic. A probe filled with something the compiler cannot type is
loud by construction; that is what made it a proof, and it is not a property a
differential harness inherits.

**2. `globals()` IS NOT SUPPORTED — `undefined variable (globals)`.** That
retires the addendum's "UNVERIFIED — do not quote it as available without
measuring it" and it retires the option with it: `if globals().get('__PXX__'):`
was the only spelling under which a superglobal was symmetric across both
compilers, and it does not compile. **So the superglobal shape has no symmetric
spelling at all**, and the import idiom is not merely preferred, it is the only
one of the two that works on both sides today. Adding `globals()` is a separate
feature and should not be smuggled in as part of this one.

**3. Arm order behaved correctly in all three arrangements I tried** — marker
import first, marker import second, and with an `else:`. That is NOT a reason to
drop the fixture requirement above. Three passing arrangements are the ones
anybody writes; the requirement is that the fixture pin the position of the
interesting import, and the two rows that matter are the ones where the LIVE arm
is lexically FIRST, which is where CLAUDE.md's first-wins defects live. Keep
that section as written.

## Still the owner's, and unchanged by any of this

The NAME and the CONTENT. He asked for dunders or other special characters;
`__pxx__` remains a seat's suggestion and not his instruction. The one sentence
that would settle the name is a goal sentence, not an implementation one:
**should an application's pxx-check be something a third party could make TRUE
on CPython by publishing a package of that name?** A claimable name says yes; a
dunder-ish one says no.

The application-side edits stay with lekkerzeilen's and TSP's own seats — the
marker is NECESSARY but not SUFFICIENT, because each application still has to
invert its own guard.

## THE FORK WAS ANSWERED; THE STRING IS NOT CONFIRMED (2026-09-20, relayed secondhand)

He answered the fork as it was put to him: **should an application's pxx-check be something a third
party could make TRUE on ordinary CPython by publishing a package of that name?** No. So the spelling
is the unclaimable one.

```python
# THE DETECTION, at the point of selection -- NOT a module-level boolean.
try:
    import __pxx__
    _backend = _pxx_backend          # the live arm under pxx
except ImportError:
    _backend = _ctypes_backend       # never compiled under pxx
```

**THE SHAPE MATTERS AND THE FIRST RELAY OF IT WAS MISLEADING — CORRECTED HERE 2026-09-20 BY
tuxspaceprogram-c6, AND IT IS RIGHT.** The relayed sketch was `HAVE_PXX = True` / `HAVE_PXX = False`
with the branch taken elsewhere. **That form defeats the entire mechanism**: a module-level boolean
tested later is a RUNTIME condition, so pxx compiles the ctypes arm anyway and the import hack's whole
purpose — the arm that cannot compile is never compiled — is lost. **The guarded import must sit
LEXICALLY where the choice is made, with the selected name bound on both arms.** TSP is already written
this way (`tsp/platform/__init__.py`, commit `98e9e66`) and was right not to adopt the sketch. Read the
boolean in any earlier relay as shorthand for "detect pxx", never as the shape to write.

**Takeable, with the spelling treated as provisional.** The PROPERTY is what was decided; the mechanism, the
measurements and the fixture requirement are already in the sections above, unchanged.

**STILL OPEN AND EXPLICITLY OURS — he was asked and deliberately did not decide them:**
- whether `__pxx__` carries target / pointer size / version, or is empty as he first suggested;
- whether `sys.implementation.name` is set alongside it.

Both are engineering. Do not send them back up.

**Wiring is already in flight on the application side:** lekkerzeilen-7a and tuxspaceprogram-c6 have
the spelling direct from frankuser and are wiring their one-line branches. **They take the final word
from the coordinator if anything about the spelling changes** — so if an implementer finds a reason
`__pxx__` cannot be the module name as spelled, that is a message to frankz-e5 BEFORE landing, not a
quiet substitution. Two applications are about to depend on the exact string.

**Unchanged and still the point:** pxx resolves the guarded import at COMPILE time, so the CPython arm
is never compiled, and the fixture must put the marker import in BOTH positions, with and without an
`else:` — a first-wins table is exposed only by the arrangement that puts the correct entry last.

### PROVENANCE OF THE NAME — read this before treating `__pxx__` as settled

**The spelling reached me through ONE channel and I have not corroborated it.** `__pxx__` was
**frankuser's own suggestion in an earlier relay, explicitly flagged at the time as NOT the owner's
instruction**, and it has now come back through that same seat as the owner's decision. That is a
circular-attribution shape, and tuxspaceprogram-c6 caught it and asked rather than assuming — correctly.

**What is actually established:** the owner was asked the fork in goal terms (*should an application's
pxx-check be something a third party could make TRUE on CPython by publishing a package of that
name?*), and the answer relayed back is **no**, which is a real decision and is the load-bearing half.
**What is NOT independently established is that the exact string `__pxx__` is his word rather than the
relay's.** Any unclaimable spelling satisfies the decision.

**Proceeding was right and holding would have bought nothing**: the module does not exist yet, so the
guarded import fails on CPython exactly as the placeholder did, and a change of spelling is a one-token
edit in each application. **Do not re-litigate it on this ticket.** If the owner's own words come back
naming a different string, the coordinator relays it and the two applications edit one token each.

## A STRAY `__pxx__.py` IS NOT A REQUIREMENT — RULED OUT, DO NOT BUILD MACHINERY FOR IT

**OWNER RULING 2026-09-20 (relayed by frankuser, secondhand), overruling the constraint this section
previously carried:** *"no. that is _not_ an issue. someone dropping a `__pxx__.py` would do so
intentionally."*

**I am making this edit on the RULE, not on the relay.** The same channel has a measured instance today
of returning its own suggestion as an instruction, so a relayed instruction is not by itself enough to
change a record — **but an existing standing rule already decides this one, and it decides it the same
way.** CLAUDE.md: *on par with the language, not with weird edge cases where the programmer actually
made a presumed error* — and **where an input is only produced by a deliberate act, matching it is not
a goal; that is `rejected/` territory, never a requirement.** The ruling and the rule agree, so the
edit stands whichever way the provenance falls.

**THE MEASUREMENT IS REAL AND STAYS; ONLY ITS STATUS CHANGES.** lekkerzeilen-7a, 2026-09-20 (lekkerzeilen
`315e6ce`, not verifiable from a pxx checkout): with a real `__pxx__.py` on the path, CPython imported
it and took the marker arm. **True, reproducible, and NOT A DEFECT** — a file of that name appears only
because someone put it there.

**So the implementer is FREE: provide the marker whichever way is simplest, including a shape CPython
could import if someone placed a file.** No un-importable-by-construction machinery. The earlier
framing — that the guarantee had to be an implementation property rather than the spelling — **is
withdrawn.**

**THE POSITIVE CONTROL IS THE ORDINARY ONE:** the check comes out **TRUE under pxx and FALSE under
CPython, with no such file present**. A control that plants a file tests a case we have ruled out.

**WHAT SURVIVES FROM 7a's MEASUREMENT AND MUST STAY LABELLED:** the third row — *a future pxx that ships
the marker takes the first arm* — is **UNTESTED**. The only way it could be exercised was with a real
file on the path, **which is not how the marker will work**. pxx did take the first arm as predicted;
that is a different claim from the one the row makes.

**Also still confirmed by measurement, and unaffected:** the nested guard is correct on both compilers
that exist today (tested with plain assignments in the arms, to avoid blocker 07's own trigger), so
**`__pxx__` is a SIMPLIFICATION for lekkerzeilen and blocker 07 is the unblocker.**

## THE GUARD IS NOT A HACK — IT IS PYTHON'S ONLY `#ifdef` (owner, 2026-09-20, relayed secondhand)

His words, immediately after ruling out the stray-file case: *"plus, we only do so due to lack of
`#define` and python's design. so, this is by design."*

**`try: import X / except ImportError:` is not a workaround. It is the ONLY conditional-compilation
mechanism the language offers** — C has a preprocessor, Python decides at import time and expects
`ImportError` to be caught. So **`__pxx__` is pxx's `#ifdef PXX`, spelled the one way Python allows**,
and NilPy resolving the guard at COMPILE time is pxx **honouring that intent rather than bending it**.

**CONSEQUENCE 1 — the ergonomics objection is settled and should not be reopened.** This idiom has been
called "the ctypes import hack" all week, by the owner himself among others. **Anyone calling it ugly
is measuring it against a preprocessor Python does not have.** No cleverer mechanism is wanted; do not
propose one, and do not rank a ticket on replacing it.

**CONSEQUENCE 2 — it reframes blocker 07 and raises it.** If the guard is Python's conditional
compilation, **a NESTED guard is nested conditional compilation, and compiling the dead arm is
compiling code the program said not to compile.** That is a correctness bug in a **language feature**,
not "an import shape we do not handle". The pxx-side ticket for 07 should carry that framing.
