---
slug: bug-n-struct-pack-with-a-computed-format-and-star-args-raises-typeerror
title: struct.pack with a computed format and star-args raises TypeError
summary: >
  `struct.pack("<%df" % n, *vals)` inside a function whose `n` is a PARAMETER
  raises `TypeError: expected a number, got object` at run time. CPython
  answers 12. Both halves are needed: the same call with a literal format and
  `*vals` is fine, and the same computed format with literal arguments is
  fine. `len(values)` in place of `n` is also fine -- it is the parameter's
  variant type flowing into the format argument, together with the star
  unpack, that breaks the dispatch.
track: N
type: bug
prio: 50
owner: unassigned
status: open
---

## Repro

```python
import struct


def k(n):
    vals = [0.0, 0.5, 1.0]
    return len(struct.pack("<%df" % n, *vals))


print(k(3))
```

`12` under CPython; `Unhandled exception: TypeError: expected a number, got
object`, rc=217, under pxx (compiler at 2026-09-14, `--threadsafe` not
required).

## The matrix -- both conditions are needed

| shape | pxx |
| --- | --- |
| `struct.pack("<%df" % n, *vals)`, `n` a parameter | **TypeError** |
| `struct.pack("<%df" % int(n), *vals)`, `n` a parameter | **TypeError** |
| `struct.pack("<3f", *vals)` -- literal format | 12 |
| `struct.pack("<%df" % n, 0.0, 0.5, 1.0)` -- no star | 12 |
| `struct.pack("<%df" % n, *vals)` with `n` a LOCAL `= 3` | 12 |
| `struct.pack("<%df" % len(values), *values)` -- `len()` is typed int | 12 |
| `"<%df" % n` on its own, `n` a parameter | `<3f` |
| the same shape calling a USER proc instead of `struct.pack` | correct |

So `%` is fine, `int()` is fine, the star unpack is fine, and the user-proc
version is fine. It is specifically `struct.pack`'s dispatch with a
variant-typed first argument AND a star unpack.

`lib/rtl`'s `struct` surface is the place to look; the message text
(`expected a number, got object`) should localise which marshalling site
raises.

## Why it matters

`gfx.py`'s `_floats` in lekkerzeilen is one character away from this shape --
it happens to use `len(values)`, which is typed `int`, and is therefore
correct. A program that passes the count in is not.

## Gate

`make test-nilpy` plus a fixture carrying the eight rows above; the six
correct rows are what localises the fix, so keep them.

## Log
- 2026-09-14 -- found while probing lekkerzeilen's renderer (the probe itself
  had this shape, which is how it surfaced). Not lekkerzeilen's bug: the app
  takes the `len(values)` arm.
