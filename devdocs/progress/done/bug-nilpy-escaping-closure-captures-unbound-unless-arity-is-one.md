---
track: N
prio: 65
type: bug
---

# A returned closure reads GARBAGE for its captures unless it takes exactly one argument

```python
def counter():
    n = 0
    def bump():
        nonlocal n
        n += 1
        return n
    return bump
f = counter()
print(f())        # CPython: 1     pxx: -443987882
```

No error, no warning — a heap/stack address printed as the value. The most
ordinary closure shape in Python (a zero-argument counter, a returned
accumulator, a callback that closes over config) is silently wrong.

## Measured boundary — it is ARITY, and only arity

The captured variable's type is irrelevant; the number of the closure's OWN
parameters decides everything.

| closure shape | CPython | pxx |
| --- | --- | --- |
| `def b():` capturing `n`, called INSIDE the parent | 42 | 42 |
| `def b():` capturing `n`, RETURNED then called | 42 | **5284453** |
| `def b(x):` capturing `n`, returned | 42 | 42 |
| `def b(x, y):` capturing `n`, returned | 44 | **5325179** |
| `def b():` capturing nothing, returned | 42 | 42 |
| capture an int / a param / a str / a list, returned | value | garbage / `''` / garbage / TypeError |

So: captures work while the parent frame is still alive, and a returned closure
works only at arity exactly 1.

## Root cause

Captures are lifted to trailing PARAMETERS appended BY THE CALL SITE
(`pyparser.inc` ≈10350: `PyHdrPNames[PyHdrNParams] := capNames[j]`). That works
only where the call site is inside the enclosing scope and can still see those
locals. A def taken as a VALUE therefore re-lowers through
`PyNestedDefClosureValue` (`pyparser.inc` ≈4317), which builds a bound compiled
function — `pyboundfn_new(addr, n, a0var)` plus one `pyboundfn_bind` per
captured value.

That path gives up here:

```pascal
  { the bridge passes exactly ONE user argument before the bound values }
  if nOwn <> 1 then Exit;
```

`Exit` returns -1, which the caller reads as "unbindable shape — fall back to
the plain address". The fallback emits the bare code address with **no captures
bound at all**, and the compiled body then reads its trailing capture
parameters out of whatever happens to be in those argument registers/stack
slots. Hence a plausible number rather than a crash.

`def b():` has nOwn = 0, so every zero-argument closure takes the bad path.

## Two fixes, and the cheap one should land first

1. **Make the bailout LOUD.** Every `Exit` in `PyNestedDefClosureValue` that is
   reached *while there is something to bind* (`PyCapCount[procIdx] > 0` or a
   defaulted param) is a silently-wrong-program, not a graceful degradation.
   Emitting `Error('Nil Python: a captured nested def taken as a value must
   take exactly one argument (arity N here) — see <this ticket>')` converts a
   garbage value into a compile error. Small, safe, and it is the project's
   stated preference: a loud gap beats a plausible wrong number. Note the
   several other `Exit`s in that function (string captures, arrays, records,
   >12 binds) have exactly the same problem and should be covered by the same
   guard.
2. **Generalise the bridge to any arity.** `pyboundfn_new` / the call bridge
   assume one user argument before the bound values; the fix is to carry the
   own-argument count alongside `a0var` and have the bridge marshal that many.
   This is the real fix and wants its own recon of the bridge's calling
   convention.

Do 1 first and independently — it is what stops a wrong value reaching a user
— then 2.

## Also note

`PyNestedDefClosureValue` bails on `tyAnsiString` / `tyString` captures
outright, so `def b(): return s` over a captured str returns `''` even at
arity 1. Same silent-fallback mechanism, same fix 1 covers it.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` covering the table
above (arity 0/1/2, capture of int, str, list and a param, called inside the
parent and after escaping), expectation taken from CPython's own output.

## Log
- 2026-07-30 — resolved, commit aad020a59.
