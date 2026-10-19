---
track: N
prio: 55
type: bug
---

# A keyword argument to a generator does not compile

Found 2026-10-19. With `def g(n, xs=None, d=acc): yield ...`, the call
`list(g(1, xs=7))` fails at compile time with `undefined variable (xs)`.
Positional `g(1, 7)` works, and so does a keyword argument to an ordinary def.
Pre-existing (12ddb7d995).
