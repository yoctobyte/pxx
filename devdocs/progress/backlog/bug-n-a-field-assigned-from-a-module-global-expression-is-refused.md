---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`G = 7 / 2` then `self.v = G` REFUSES to compile — \"cannot infer the type of field self.v - annotate it\". `G = 3.5` is accepted. PyModuleGlobalLiteralType reads a global's type off its initialiser token and can only see a bare LITERAL, so any global initialised by an expression is untypeable to the field pre-pass."
---

# A field assigned from a module global whose initialiser is an EXPRESSION is refused

- **Type:** bug (Track N — Nil Python frontend) — hard compile refusal of code
  CPython runs, so it is on the wrong side of the upward-compatibility rule.
- **Filed:** 2026-08-26 by frank1-N-truediv, found while varying shapes for
  [[bug-n-inferred-return-type-of-true-division-is-int]].

## Repro

```python
G = 7 / 2

class D:
    def __init__(self):
        self.v = G
    def get(self):
        return self.v

print(D().get())        # CPython 3.5;  pxx: refuses to compile
```

```
pascal26:5: error: Nil Python: cannot infer the type of field self.v - annotate it (self.v: int = ...)
```

The control that works: `G = 3.5` compiles and prints 3.5. So it is the
initialiser's SHAPE, not the global-ness.

## Cause

`PyModuleGlobalLiteralType` (`compiler/pyparser.inc`) exists precisely because
the field pre-pass runs before `PyCollectModuleLocalsAST`, and it types a global
by reading its initialiser token. A bare literal it can read; `7 / 2`,
`f(1)`, `[1] + [2]`, `A + B` it cannot, and the caller then falls through to the
`ErrorAt` that rejects the whole program.

Any expression-initialised global hits this — `MAX = 1 << 20`, `TAU = 2 * 3.14159`,
`NAMES = ["a"] + EXTRA` — so the blast radius is much wider than division.

## Fix shape

`PyModuleGlobalLiteralType` already knows where the global's initialiser starts;
hand the whole initialiser range to `PyInferExprType` when the single-token read
comes back `tyUnknown`, the same fallback the field pre-pass itself uses one
level up. That reuses the one expression scanner instead of growing a second
half-scanner, which is the note already written beside the field arm.

If the expression scanner still cannot type it, the current `ErrorAt` is a
defensible last resort — but it should not be reached by `G = 7 / 2`.

## Gate

A `.npy` diffed against CPython: a field assigned from a module global
initialised by `/`, by `<<`, by a list concatenation, by a call, and by a
construction; plus the bare-literal controls (int / float / str / bool / list)
that already work.
