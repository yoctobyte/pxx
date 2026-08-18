---
track: N
prio: 40
type: bug
blocked-by: []
summary: "str(e) on an exception class declared in a Pascal unit dispatches __str__ by the STATIC type of the except clause, not the runtime type: `except URLError as e` gives '<urlopen error boom>' and `except Exception as e` gives 'boom' for the same object. CPython gives the same string either way. Pure-NilPy classes are NOT affected."
---

# `str(e)` ignores a Pascal-declared exception's `__str__` when caught as a base

- **Type:** bug (Nil-Python frontend) — **Track N**.
- **Filed:** 2026-08-18 by frank3-b, while writing `lib/rtl/mimic_urllib_error.pas`
  ([[feature-b-mimic-urllib-request-over-the-rtl-http-stack]]).

## The bug

`str()` picks the `__str__` implementation from the **static** type named in the
`except` clause instead of the object's **runtime** type. Catching the same
object as its own class and as a base class produces two different strings.

## Repro

`lib/rtl/mimic_urllib_error.pas` is already in the tree and declares
`URLError` with a `__str__`, so the repro needs no new Pascal:

```python
from urllib.error import URLError

def make():
    return URLError("boom")

for clause in ("URLError", "Exception", "OSError"):
    pass   # spelled out below, one try per clause

try:    raise make()
except URLError as e:   print("as URLError:", str(e))
try:    raise make()
except Exception as e:  print("as Exception:", str(e))
try:    raise make()
except OSError as e:    print("as OSError:", str(e))
```

pxx (pinned, HEAD `df15ae3fe`):

```
as URLError: <urlopen error boom>
as Exception: boom
as OSError: boom
```

CPython:

```
as URLError: <urlopen error boom>
as Exception: <urlopen error boom>
as OSError: <urlopen error boom>
```

## What was measured, including two things it is NOT

- **Not general to NilPy classes.** A pure-NilPy `class Sub(Base)` with a
  `__str__`, passed through an unannotated parameter, stringifies correctly in
  both pxx and CPython. So the runtime-dispatch machinery works; this is about a
  **Pascal-declared** class reached from NilPy.
- **Not the sysutils/pylib `Exception` shadowing hazard**, which is a different
  and *deliberate* thing that bit this same investigation first. A Pascal unit
  doing `uses pylib, sysutils` gets **sysutils'** `Exception` for a bare
  `Exception`, so `MyErr = class(Exception)` lands in the wrong tree and does not
  stringify as a Python exception at all. That is the documented sibling-class
  design (see pylib.pas's header), not a defect, and `mimic_urllib_error.pas`
  sidesteps it by descending from `OSError`, which only pylib declares. Recorded
  here because the two look identical from the NilPy side and the first
  diagnosis written down was the wrong one of the two.
- The `.msg` attribute is correct in every case — only `str()` differs.

## Why it matters

`except Exception as e: log(str(e))` is the single most common way a program
handles an error it did not anticipate, and that is exactly the path that loses
the message. The wrong string is *plausible* — it is the bare message rather
than nonsense — so nothing looks broken.

## Impact today

`lib/rtl/mimic_urllib_error.pas` (`URLError`, `HTTPError`,
`ContentTooShortError`). Their CPython-diffed test catches them by their own
class names, which is the arm that works, so the suite stays green and this bug
is invisible to it — deliberately noted so nobody reads a green
`lib_mimic_urllib_request` as evidence this is fixed.
