---
track: N
prio: 45
type: feature
---

# NilPy: the remaining missing builtins — min/max, list(), reversed(), enumerate(), hex()

Swept 2026-07-20 against CPython. All of these fail LOUDLY ("undefined
variable"), which is why they are one low-priority ticket rather than
several: none of them can produce a wrong answer, unlike
[[bug-a-nilpy-int-of-string-returns-a-pointer]] found in the same sweep.

| builtin | uforth sites | shape |
| --- | --- | --- |
| `min` / `max` | 7 + 7 | two-argument only; trivial |
| `list(x)` | 21 | copy an iterable into a new TPyList |
| `reversed(x)` | 7 | needs an iterator, or a reversed copy |
| `enumerate(x)` | 4 | needs [[feature-nilpy-tuple-unpack]] to be useful |
| `hex(n)` | 1 | `pyformat_of(n, "x")` with an `0x` prefix |

## What already works, for the record

`len`, `abs`, `ord`, `chr`, `isinstance`, `int` of a NUMBER, `str` of a
number, `//`, `%`, `/`, unary minus. `**` is absent and has ZERO uforth
sites, so it is not worth doing for this corpus.

## Shape

`min` / `max` / `list` / `hex` are plain pylib FUNCTIONS — neither name is a
Pascal keyword, so they resolve through the normal call path with no frontend
hook, the same way `bytearray` and `bytes` do (6468ff22). That makes them a
half-hour of work between them.

`reversed` and `enumerate` are not: both are iterator protocols in Python, and
NilPy's `for` is a counted-loop desugar with no iterator concept. Either give
`for` a second desugar for each of them (cheap, closed-world) or wait for a
real iterator model. `enumerate` additionally needs tuple unpacking to be
worth anything.

## Gate

`test-nilpy` green with a `.npy` case diffed against CPython + `--tier quick`
+ self-host byte-identical + `make fpc-check`.
