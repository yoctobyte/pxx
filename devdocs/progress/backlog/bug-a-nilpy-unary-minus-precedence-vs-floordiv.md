---
track: A
prio: 70
type: bug
---

# NilPy: unary minus binds LOOSER than `//` and `%` — `-7 // 2` is -3, not -4

Found 2026-07-20 while landing
[[bug-a-nilpy-floordiv-and-modulo-wrong-for-negatives]]. Separate root cause,
left unfixed deliberately: that ticket was about the floor SEMANTICS, this is
about PRECEDENCE.

## Repro

```python
print(-7 // 2)     # CPython -4  -> pxx -3
print(-7 % 2)      # CPython  1  -> pxx -1
print((-7) // 2)   # CPython -4  -> pxx -4     (correct with parens)
```

Silent, plausible, off by exactly one.

## Root cause

The shared parser gives unary minus Pascal's precedence, where it binds looser
than `div`/`mod` — `-7 div 2` really is `-(7 div 2)` in FPC, so the Pascal
behaviour is right and must not change. Python binds unary minus TIGHTER than
`//` and `%`, so `-7 // 2` is `(-7) // 2`.

Only NON-DISTRIBUTIVE operators expose it, which is why nothing caught it:
`-7 * 2`, `-7 + 2` and `-7 / 2` give the same answer either way, so `*`, `+`
and `/` all look fine. `//` and `%` are the whole observable surface today;
`**` will join them when it lands, and it will be worse (`-2 ** 2` is -4 in
Python).

## Shape

This is the same category as [[bug-a-nilpy-and-or-in-unavailable-in-call-arguments]]
and the rest of group 4: the shared parser's expression layers do not know
NilPy's rules, because `pyparser.inc` owns only the bitwise and boolean
layers. Fix the precedence where that group's design decision lands — a
PyExprMode-gated unary-minus binding — rather than as a one-off, and cover
`**` at the same time so the answer does not have to be found twice.

## Gate

`make test` + self-host byte-identical, `test-nilpy` green, and the three
repros above matching CPython. Add a sweep of unary minus against `//`, `%`,
`*`, `/`, `+` for both signs of both operands — the distributive cases are
what hid this.
