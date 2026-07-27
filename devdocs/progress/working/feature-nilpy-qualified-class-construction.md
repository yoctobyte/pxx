---
summary: "nilpy: unit-qualified class construction (`tk.Frame(...)`)"
type: feature
track: N
prio: 55
---

# nilpy: unit-qualified class construction

- **Type:** feature (Nil-Python frontend) — **Track N**
- **Opened:** 2026-07-27 — found while landing `import X as Y`
  ([[feature-demo-songformatter-pxx-target]]).

## Repro

```python
import tkinter as tk
root = tk.Tk_()                                  # a FUNCTION: works
v = tk.StringVar()                               # error: expected expression
f = tk.Frame(root, highlightthickness=0)         # error: unexpected token
```

Both failures reproduce with the real module name too (`tkinter.StringVar()`), so
this is about QUALIFICATION, not about the alias.

## Why

The NilPy ctor intercept in `ParseFactor` (parser.inc, "ClassName(args) in ANY
expression position is construction") fires only when the class name is the
CURRENT token and the very next token is `(`. With a qualifier the cursor sits on
the unit name, so the whole thing falls through to the Pascal qualified-call path,
which knows how to resolve a qualified PROC (that is why `tk.Tk_()` works) but not
how to construct a class — and it certainly does not do NilPy keyword arguments.

## Shape

Extend the intercept: when the tokens are `ident . ident (`, the first ident is
not a symbol and does name a unit or alias (`FindUnitOrAlias`), and the second
names a class type, consume the qualifier and hand off to `PyClassCreate` exactly
as the unqualified form does. Unit scope is flat, so the class resolves by bare
name once the prefix is consumed — the qualifier only has to stop being a parse
error.

## Why it matters

`tk.Frame(...)`, `tk.Canvas(...)`, `tk.StringVar()` are how real tkinter code is
written, and songformatter's `settings.py` and `convertrawtext.py` both use the
qualified spelling throughout. The façade itself is already in
([[feature-nilpy-tkinter-facade]]); this is what stands between it and the
application's actual source.

## Gate

`make test-nilpy` green with a `.npy` case covering a qualified ctor with and
without keyword arguments, `--tier quick`, self-host byte-identical.
