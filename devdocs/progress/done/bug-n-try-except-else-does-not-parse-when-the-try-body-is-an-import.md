---
track: N
prio: 50
type: bug
status: done
owner: ""
created: 2026-09-11
found-by: frankuser
tags: [nilpy, imports, syntax, lekkerzeilen]
blocked-by: []
summary: "`try: import X / except ImportError: ... / else: ...` fails with `error: expected expression` ON THE `else:` LINE. try/except/else itself WORKS -- with plain statements in the try body, and even with an import in the ELSE body. It is specifically a GUARDED IMPORT in the try body that loses the else clause, which fits: a guarded import is special-cased as a compile-time decision rather than a runtime try, and that path does not know about `else`. Measured 2026-09-11 at c53cb51926a2. Live cost: this is the shape the lekkerzeilen backend seam WANTS, so the rewrite that took the demo 25 -> 27 had to accept a behaviour difference instead."
---

# `try: import X ... else:` — the else clause does not parse

Measured 2026-09-11, compiler `c53cb51926a2`. The discriminator set is the whole
ticket, because three of these four pass:

| shape | pxx |
| --- | --- |
| `try: x = 1 / except ValueError: / else: print(...)` | ok |
| `try: x = 1 / except ValueError: / else: import math; ...` — import in the ELSE | ok |
| `try: import nosuchmod / except ImportError: / else: print(...)` | **`pascal26:5: error: expected expression`** on the `else:` |

So `try/except/else` is implemented (`pyparser.inc:22523` has the `__tryelse`
flag mechanism, and `for`/`while` else are done), and an import is fine in the
else body. **Only an import in the TRY body breaks it.**

That fits the design rather than contradicting it: a guarded import is a
COMPILE-TIME decision — pxx decides which arm is live and does not compile the
dead one — so `try: import X` is not really a runtime try, and the path that
handles it never reaches the `else` parse. The error is a parse error, not a
lowering one, which is consistent.

## Why this is prio 50 rather than a syntax curiosity

**It is the shape the lekkerzeilen seam wants.** `platform/__init__.py` selects a
backend, and the faithful spelling is:

```python
try:
    import ctypes
except ImportError:
    from . import _pxx as _backend          # native
else:
    from . import _ctypes_backend as _backend   # the else keeps this OUT of the try
```

The `else` is load-bearing: it puts the ctypes-side import outside the try's
exception coverage, so an `ImportError` raised *by that module itself* propagates
instead of being swallowed into the fallback. Because the else does not parse, the
rewrite that took the demo from 25 to 27 of 35 (corpus `8fb873d`) had to put that
import inside the try and **accept a real behaviour difference**, documented in the
corpus source. Any Python codebase that selects an optional backend is likely to
reach for the same three-clause shape, which is why the exposure is wider than one
demo.

## Not this

- `for`/`while` else: done, and working.
- try/except/else with a plain try body: working. Do not "fix" the general case.
- `try: import X` itself: working, and the dead-arm handling was fixed at
  `bug-n-a-dead-guarded-import-arm-still-compiles-the-module-it-imports`.

The fix is narrow: wherever the guarded-import arm is recognised, let it fall
through to the same `else` handling the ordinary try path already has.

## Positive control for whoever fixes it

Both of these must pass afterwards, and the second is the one that catches an
over-broad fix — it must still take the `else` arm, not the except arm:

```python
try:
    import nosuchmod
except ImportError:
    R = "fallback"
else:
    R = "present"
# R == "fallback" under pxx AND CPython, because nosuchmod does not exist

try:
    import math
except ImportError:
    S = "fallback"
else:
    S = "present"
# S == "present" both ways
```

Asserting only the first would pass for an implementation that always takes the
except arm.

**Both expected values above are MEASURED under CPython, not predicted** —
`fallback` and `present` respectively. And both fail under pxx today with the
identical `pascal26:5: error: expected expression`, **whether the imported module
exists or not**, which is the evidence that this is parse-time and not resolution:
`import math` succeeds and still loses the else.

## RESOLVED — fixed at `cc311ec6e`, VERIFIED HERE WITH THIS TICKET'S OWN CONTROLS

Fixed by a peer who credited the filing. Verified at binary `465845b20d1e`, using
the two controls written above rather than a fresh probe:

| control | CPython | pxx |
| --- | --- | --- |
| `try: import nosuchmod / except ImportError: R="fallback" / else: R="present"` | `fallback` | **`fallback`** |
| `try: import math / except ImportError: S="fallback" / else: S="present"` | `present` | **`present`** |

**The second row is the one that matters** — it is the control this ticket named
for catching an over-broad fix, because an implementation that always took the
except arm would pass the first row alone. It takes the `else`.

The mechanism, from the fix's own commit message: `PyParseFallbackImportTry` now
consumes the `else` on both arms — **skipped unparsed** when the handler ran
(parsing resolves imports, and that block sits on the branch the program does not
take) and folded onto the tail of the try body when it did not. Which is why the
ordinary try path had handled `else` correctly all along: this was never a general
parser gap.

**The consequence is banked, not merely noted.** The lekkerzeilen seam is back on
the faithful spelling, so the behaviour difference this bug forced — an
`ImportError` raised by `_ctypes_backend` itself being swallowed into the native
fallback — is **gone** rather than documented. That was the whole reason this was
prio 50 instead of a syntax curiosity.
# Fixed 2026-09-11, frankZ — and the prescribed fix was the half that does not matter

Compiler `8b0839edde8f`. Both of the positive-control rows above now answer
`fallback` and `present`, matching CPython, and they were re-derived from the
built binary rather than copied from this ticket.

## The fix was NOT narrow, and the narrow half alone is a silent wrong value

This ticket prescribed it: *"wherever the guarded-import arm is recognised, let
it fall through to the same `else` handling the ordinary try path already has."*
That reading of the parse failure was exactly right, and doing only it produces
a compiler that **compiles the construct and answers the wrong module**.

**Layer 1 — `PyParseFallbackImportTry`.** The `else` is consumed on both arms:
skipped when the handler ran (never parsed — parsing resolves imports, and that
block is on the branch the program does not take), and folded onto the tail of
the try body when the guard resolved. It has to be consumed BEFORE the dead-tail
skip, which runs only when the handler exits; without that ordering an `else`
after a non-exiting handler still reached the caller untouched.

**Layer 2 — `PyPreScanImports`, and this is the one the ticket could not see.**
That walk resolves every import token in the file with no notion of
reachability. With only layer 1 in place:

```
hit ('else', 'fallback', 2)        # pxx
hit ('else', 'selected', 2)        # CPython
```

Exit 0, no diagnostic. The control flow is visibly right — pxx takes the `else`
and says so — and `impl` is the module the program did not select. The prescan
had bound the DEAD handler's unit alias, and `FindUnitOrAlias` is first-wins
(`bug-n-a-unit-alias-rebind-is-silently-ignored`), so the live arm's rebind is
appended after it and never reached. The walk now tracks which ARM a clause is
and skips the dead one: the handler when the guard resolved, the else when it
missed. `guardSeen` separates a compile-time branch from an ordinary runtime
try, whose handler and else are both live and whose imports must still resolve.

Two layers resolving imports, and fixing either alone changing nothing, is
recorded twice already in the prescan's own comments. This is the third
instance, and it is the first where the parser-only fix **passes its own
repro**.

## Why it survived: an `else` is what makes the defect visible

In the ordinary no-`else` idiom the LIVE arm is lexically first in **both**
outcomes — the try body's import when the guard resolves, the handler's when it
misses — so first-wins gives the right answer by POSITION and the dead arm's
binding is structurally invisible. `else:` inverts that: it puts the live arm
AFTER the dead handler. Two rows of the new fixture were passing for that reason
before the third was read.

The same arm skip also removed a dead arm's imported SYMBOL binding
(`from .mod import N as Z` in a dead arm was visible at module scope where
CPython raises `NameError`), which reproduces with no `else` in the file at all
and had been filed here as pre-existing before it was re-measured.

## Fixture

`test/test_nilpy_try_except_else_with_an_import_in_the_try_body.npy` with
`test/nilpy_tryelse/`, wired beside the getattr fold. Rows: guard misses →
handler runs and else does not; guard resolves → else runs, handler does not,
and the else's own body including a use of the module the try imported is live.
Both import spellings, because they reach the arm skip by different doors.

**No row guards on `ctypes`.** The construct's real use is backend selection,
where CPython resolves ctypes and pxx does not — oracle and subject would run
DIFFERENT arms and the differential could never fail. Both guards are decided
identically under both runtimes.

Positive control against the parent commit `785b25831252`:
`pascal26:36: error: expected expression / in: test/nilpy_tryelse/__init__.py`.

## The seam

The faithful spelling this ticket was filed for now compiles:

```python
try:
    import ctypes
except ImportError:
    from . import _pxx as _backend
else:
    from . import _ctypes_backend as _backend
```

pxx prints `pxx`, CPython prints `ctypes` — both correct, each taking its own
runtime's live arm. The corpus rewrite that had to use the unfaithful spelling
and document a behaviour difference can be reverted to this; that is a
lekkerzeilen-side change and is not done here.

## Not fixed, and measured so

An ORDINARY runtime try whose handler and else each bind the same alias answers
the handler's module. Identical on `785b25831252` and `8b0839edde8f`, so it is
untouched by this work and is not a regression from it:
`bug-n-a-unit-alias-bound-in-both-arms-of-a-runtime-try-answers-the-handler-s-module`.
A unit alias is a compile-time table and that branch is a runtime one.

## Log
- 2026-09-11 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 7958322f8.

## Verification status — stated because it is partial

- **Self-host fixedpoint:** converged, `8b0839edde8f`.
- **The fixture's own row:** PASSED inside the tier, and separately against
  CPython by hand on both spellings.
- **Positive control:** holds against the parent commit `785b25831252`.
- **`make test-nilpy`: INCOMPLETE, and not because of a red.** Two runs were
  killed by the host's memory reaper — 413 rows on the first, **389 of 957
  compile invocations** on the second, zero failures in either, the second
  stopping at `test_nilpy_sorted_key_dispatch`. Everything after that point in
  Makefile order was **never reached** and this change is unverified against it.
  The competing load is the owner's own `tools.import_nl` terrain build (~9GB,
  run in a series), identified by frankuser, so a third attempt would be killed
  the same way; landed on partial evidence rather than holding the seat, per
  NEVER WAIT.
- **Track T breadth:** `9e9d85955260 GREEN` **predates** this fix, so it covers
  none of it. No breadth evidence exists for this change yet.

## Reconciling the two resolutions above — both are correct and one is incomplete

Two seats resolved this independently, from different binaries (`465845b20d1e`
and `8b0839edde8f`), with the same verdict on this ticket's own two controls.
That is corroboration and both write-ups are kept.

**One correction to the earlier section's MECHANISM summary**, which reads the
fix as layer 1 only: *"`PyParseFallbackImportTry` now consumes the `else` on both
arms"*. True, and it is **half** of `cc311ec6e`. The commit also taught
`PyPreScanImports` which ARM is dead, and **that half is the load-bearing one**:
with only the parser taught, the construct COMPILES and binds the dead arm's
module — `('else', 'fallback', 2)` against CPython's `selected`, exit 0, no
diagnostic — because the prescan resolves every import in the file with no notion
of reachability and `FindUnitOrAlias` is first-wins.

This matters beyond bookkeeping: a reader who takes the summary at face value
would conclude the parser is the whole story, and that is exactly the conclusion
that produces a silent wrong value. Two layers resolve imports here and fixing
either alone changes nothing — recorded twice already in the prescan's own
comments, and this is the third instance.

**The seam claim is the other seat's and is theirs to stand behind:** they report
lekkerzeilen back on the faithful spelling. This seat verified that the faithful
spelling COMPILES and that each runtime takes its own correct arm; it did not
make the corpus change.
