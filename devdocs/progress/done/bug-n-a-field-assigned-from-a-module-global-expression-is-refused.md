---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`G = 7 / 2` then `self.v = G` REFUSES to compile — \"cannot infer the type of field self.v - annotate it\". `G = 3.5` is accepted. PyModuleGlobalLiteralType reads a global's type off its initialiser token and can only see a bare LITERAL, so any global initialised by an expression is untypeable to the field pre-pass."
status: done
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

---

## Fixed 2026-09-09 — and the one sub-case that is NOT this ticket

Implemented as the "Fix shape" section prescribes: when the single-token
readers come back `tyUnknown` and the initialiser is more than one token, the
range goes to `PyInferExprType`, the same scanner the field pre-pass one rung
up already falls back to. Measured against CPython, all matching:

| global | was | now |
| --- | --- | --- |
| `G = 7 / 2` | refused | `3.5` |
| `MAX = 1 << 20` | refused | `1048576` |
| `TAU = 2 * 3.14159` | refused | `6.28318` |
| `NAMES = ["a"] + EXTRA` | refused | `b` |
| `OPTS = {"a": 1}` | ok | ok |

The container row needed one extra line rather than the scanner: an expression
whose first token opens a list or dict answers `tyVariant`, which is what the
BARE list/dict branch two arms up already answers for the same global. Widening
an arm that exists, not adding a reader.

**NEVER `tyClass` from here, and that is the row this change could have broken
silently.** `G = K()` needs the class IDENTITY and not merely the kind —
`PyModuleGlobalCtorClass`, the caller's next arm, is what carries it, and
answering `tyClass` here would set `fldRec` to `REC_NONE` and read the field at
the wrong layout. That is the recorded `5887615` where CPython says `9`, and it
does not fail to compile. Excluded explicitly, and asserted by a control row in
`test/test_nilpy_field_from_a_module_global_expression.npy`.

### Still refused, pre-existing at the pin, and a DIFFERENT rung

```python
def named(x):
    return x + 1

FN = named            # a global bound to a def

class C:
    def __init__(self):
        self.fn = FN  # cannot infer the type of field self.fn
```

`self.fn = named` reading the def DIRECTLY works — that is
`bug-n-a-field-assigned-a-module-level-def-has-no-inferable-type`, closed. One
level of indirection does not, because `PyModuleGlobalIsDef` asks whether the
name is itself a `def` and not whether it is a global HOLDING one. It is a
single-token initialiser, so it never reaches the expression fallback added
here, and it is out of this ticket's subject. Refused at the pin too, so it is
not a consequence of this change. Worth its own ticket if anyone hits it in
real source; the alias idiom (`update = __init__` at module scope) is where it
would show up.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit c4e6d55d0.
