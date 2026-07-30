---
track: N
prio: 80
type: bug
---

# `nonlocal x` — the write never reaches the enclosing function

```python
def outer():
    y = 1.0
    top = 800.0

    def headers():
        nonlocal y
        y = top
        y -= 9.0

    headers()
    return y

print(outer())      # CPython: 791.0    pxx: 1.0
```

Silent: it compiles, runs, and returns the value the enclosing function started
with. `nonlocal` is ACCEPTED (no diagnostic) and then ignored.

## Cause, as far as it is measured

A nested def's captures are passed as trailing parameters BY VALUE
(feature-nilpy-nested-defs) — "Python reads a closed-over name at call time, so
its value at the call site is the right one". That is true for READS and wrong
for WRITES: a `nonlocal` assignment updates the callee's copy, which is
discarded at return.

## Why it matters here

songformatter's page layout is built this way — `printHeaders()` does
`nonlocal y; y = pagetop` and then decrements `y` down the page, and every later
line places text at that `y`. With the write lost, every header lands at the
value `y` happened to hold before the call. It is not what crashes the render
([[bug-nilpy-songformatter-first-render-walls]]), but it would misplace
everything once the crash is fixed.

## Shape of a fix

The capture would have to be by REFERENCE for names the nested def declares
`nonlocal` (the others can stay by value). That is a per-name decision the
capture scan already has the information for: it reads the body, so it can see
which names are under a `nonlocal` statement and pass those as `var`.

An honest interim, if the fix is deferred: REJECT `nonlocal` with a diagnostic
rather than accepting it and dropping the write.

## Gate

`make test-nilpy` plus a `.npy` covering read-only capture, a `nonlocal` write,
and a `nonlocal` write in a def called twice, diffed against CPython.
