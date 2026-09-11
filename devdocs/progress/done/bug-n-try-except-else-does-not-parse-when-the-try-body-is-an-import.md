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
