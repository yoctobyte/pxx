---
summary: "nilpy: a method parameter that is unannotated AND has a default fails to parse; the obvious fix returns wrong values"
type: bug
track: N
prio: 65
---

# nilpy: `def m(self, a, b=None)` — unannotated parameter with a default

- **Type:** bug (Nil-Python frontend, method header) — **Track N**
- **Status:** backlog
- **Opened:** 2026-07-26. This is the wall `convertrawtext.py` sits on (line 1603,
  `FormatText.__init__(self, parent, on_next, on_change=None)`), the last one
  before that module compiles.

## Repro

```python
class C:
    def __init__(self, parent, cb, on_change=None) -> None:
        self.parent = parent
        self.cb = cb
        self.on_change = on_change

c = C("p", "f")
print(c.parent, c.cb)
```
```
Expected: ), but got:  (Kind: 63, Line: 2)
pascal26:2: error: unexpected token
```

At MODULE level the same shape is fine — `def f(a, b=None)` compiles. It is
specific to a METHOD.

## Cause, and why the obvious fix is not enough

`PyParseMethod` has two parameter branches. The ANNOTATED one steps over `= value`
after reading the annotation; the UNANNOTATED one does not, so the cursor stays on
the `=` and the parameter list fails to close.

Adding the same skip to the unannotated branch makes it COMPILE — and the program
then prints an EMPTY line where CPython prints `p f`. So the arguments no longer
arrive in the right slots: reading `c.parent`/`c.cb` gives nothing. That is silent
wrong output, worse than the parse error, so the one-line skip was reverted rather
than shipped.

The likely cause is a disagreement between this reader and the pre-pass about the
parameter list: the pre-pass records the default and the registered signature,
`PyParseMethod` builds the frame, and the comment above the annotated branch says
in as many words that "the two must agree: ... a disagreement is a silent ABI
mismatch". Whoever fixes this should check the parameter COUNT and the default
recording on both sides for the unannotated-with-default case, not just the cursor
position.

## Gate

`make test-nilpy` green with a `.npy` case that constructs such a class BOTH with
and without the defaulted argument and prints every field, diffed against CPython
— the parse alone is not evidence, as above.
