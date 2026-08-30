---
track: N
prio: 50
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

## 2026-08-30 (frankB) — a stronger case, and the reason to rank this above 50

Found while writing `test/lib_mimic_urllib_error.npy`
([[feature-b-sweep-mimic-shims-against-cpython]]). Measured at pin v395, not
reasoned.

### It is not "falls back to the base's generic stringify" — it is genuinely static

The case on record is `except Exception`, a base that declares no `__str__` of
its own, which is consistent with a *fallback*. It is not a fallback. An
**intermediate** class that DOES declare `__str__` loses the derived one just
the same:

```python
try:
    raise HTTPError('http://x/', 500, 'Boom', None, None)
except URLError as e:
    print(str(e))
```

| | pxx | CPython |
| --- | --- | --- |
| `except HTTPError as e: str(e)` | `HTTP Error 500: Boom` | `HTTP Error 500: Boom` |
| `except URLError as e: str(e)` | **`<urlopen error Boom>`** | `HTTP Error 500: Boom` |
| `except OSError as e: str(e)` on a `URLError('nope')` | **`nope`** | `<urlopen error nope>` |

Every class in that chain declares `__str__`, and the clause picks whichever
one its own static type declares. Only a clause naming the object's **exact**
class is right.

### Why that is worth more than p50

The two wrong rows are not exotic arms — they are the two idioms this exact
module exists to serve, and the shim's own header names both:

- `except URLError as e: log(str(e))` is *the* idiom for urlopen in the wild,
  and it drops the **HTTP status code** — the single most useful token in the
  message. A 500 and a 404 become indistinguishable in the log.
- `except OSError` around urlopen is common enough that
  `mimic_urllib_error.pas` calls the OSError ancestry "load-bearing" for it,
  and that arm loses the `<urlopen error ...>` wrapper entirely.

Both produce a **plausible wrong string** rather than an error, so nothing
fails — which is the expensive shape, not the cheap one.

The header of `mimic_urllib_error.pas` asserted, until today, that its
`__str__` methods "are what makes the common arm right today". That was never
measured and is false; the comment is corrected in the same commit as this
note. Recommending **p60**, but leaving `prio:` alone — Track N owns the
number.

### Not blocking the shim's gate

`test/lib_mimic_urllib_error.npy` (42 checks, byte-identical) asserts **which**
clause catches which object and skips **what `str()` prints inside a base-class
clause**, with the divergence named in its docstring and in the Makefile.
Asserting it would make the file fail under one interpreter. So this bug is
recorded, not papered over, and the gate goes green without pretending.
