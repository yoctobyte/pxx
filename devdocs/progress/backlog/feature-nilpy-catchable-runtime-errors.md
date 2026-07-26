---
summary: "nilpy: builtin runtime errors must raise catchable exceptions (int(), division by zero)"
type: feature
track: N
prio: 55
---

# nilpy: builtin runtime errors are not catchable

- **Type:** feature (Nil-Python frontend, exception model) — **Track N**
- **Status:** backlog
- **Opened:** 2026-07-26 — probing songformatter under nilpy
  ([[feature-demo-songformatter-pxx-target]]).

## Repro

```python
try:
    x = int("nope")
except ValueError:
    print("caught ValueError")     # never reached
# -> Runtime error: int() got a string that is not a number: nope  (process aborts)

try:
    x = 1 // 0
except:
    print("caught")                # never reached
# -> Runtime error 200 (division by zero)  (process aborts)
```

`raise ValueError("mine")` from Python code IS caught, so the machinery works —
what's missing is that errors raised by the runtime itself don't enter it.

## Why it matters

Guarding a conversion with try/except is how real Python validates input.
songformatter relies on it: settings parsing (`int(get(...))`) and the `image=`
size/position parsing are wrapped in try/except and are expected to fall back to
defaults, not abort the render.

## Shape

Raise the builtin exception types from the runtime helpers (`ValueError` from
int()/float() conversions, `ZeroDivisionError`, `IndexError`, `KeyError`) so the
existing handler path catches them, including a bare `except:`.

## Gate

`make test-nilpy` green with a `.npy` case per error type diffed against CPython,
+ `--tier quick` + self-host byte-identical.
