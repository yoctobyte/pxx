---
summary: "NilPy survey: repr(), __iter__/__next__, __getattr__, __delitem__ and a custom __hash__ are unsupported — all fail LOUDLY (compile error or raise), measured vs CPython"
type: bug
track: N
prio: 35
---

# Unsupported protocols: `repr()`, `__iter__`/`__next__`, `__getattr__`, `__delitem__`, `__hash__`

- **Type:** bug (NilPy, missing protocol support) — **Track N**
- **Opened:** 2026-08-01, from the CPython differential sweep (1094 cases,
  self-hosted binary at `3f2c5b915`).

A **survey ticket**, deliberately: these were found in one pass and share a
cause (the protocol is simply not implemented), but they are separate features.
Split into per-protocol tickets when picked up — do not treat this as one job.

## Why the low priority despite being real

Every one fails **loudly** — a compile error or a raise, never a wrong value.
That puts them well below the silent-wrong findings from the same sweep
([[bug-nilpy-bool-protocol-ignored-object-always-truthy]],
[[bug-nilpy-unary-numeric-dunders-return-raw-handle]],
[[bug-nilpy-ne-dunder-ignored-always-negates-eq]]) and below the one that
crashes ([[bug-nilpy-bitwise-shift-on-class-operand-segfaults]]).

## Measured

| case | CPython | pxx |
| --- | --- | --- |
| `repr(c)` | `REPR` | *compile error*: `undefined variable (repr)` |
| `for x in Countdown(3)` (`__iter__`/`__next__`) | `2 1 0` | *compile error*: `pylib (count) not loaded` |
| `C().missing_thing` with `__getattr__` | `GETATTR-missing_thing` | *compile error*: `"missing_thing": no such member on this record/class` |
| `del c[3]` with `__delitem__` | `DELITEM 3` | *compile error*: `del is supported on a dict subscript or a list slice` |
| `d[C(1)]` with `__hash__`+`__eq__` | `one` | `KeyError: key not found` |

### Notes per item

- **`repr()` is not a builtin at all.** `__repr__` *is* known to the compiler
  (it is used when printing), but the `repr(x)` function does not exist. Likely
  the smallest of these and the most commonly written.
- **`__iter__`/`__next__`**: `for x in <user object>` assumes a pylib container
  and looks for `count`. A custom iterator class is a normal Python idiom;
  supporting it means teaching the for-loop lowering the iterator protocol
  (including `StopIteration`), not just adding a name.
- **`__getattr__`**: attribute lookup is resolved statically against the class
  layout, so a dynamic fallback needs a runtime path — the largest of the five
  and the one most entangled with how NilPy types attributes today.
- **`__delitem__`**: `del` already handles dict-subscript and list-slice; this
  is the user-class arm of an existing construct.
- **`__hash__`**: a user object as a dict KEY. Related to, but distinct from,
  [[bug-nilpy-dunders-not-dispatched-through-containers]] — that one is about
  dunders on an instance *inside* a container; this is the instance being used
  as the container's key, needing `__hash__`/`__eq__` at runtime. Whatever
  [[decide-nilpy-runtime-dunder-dispatch-mechanism]] decides will likely settle
  this one too, so check that ticket before starting.

## Gate (per split-out ticket)

`make test-nilpy` + self-host byte-identical, plus a `.npy` diffed against
CPython's own output for the protocol in question, and a case where the class
does NOT implement it (must raise a catchable error, not compute garbage).
