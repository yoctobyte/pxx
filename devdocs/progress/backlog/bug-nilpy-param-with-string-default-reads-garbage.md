---
track: N
prio: 75
type: bug
---

# A parameter with a STRING default is read as garbage

Pre-existing — reproduces on `stable_linux_amd64/default/pinned`, where it
prints a raw pointer value. Silent: compiles clean, wrong at run time.

```python
def f(a="A"):
    return a

print(f("z"))     # CPython: z     pxx: (empty)   pinned: 129441380433944
print(f())        # CPython: A     pxx: (empty)
```

Annotating does not help (`def f(a: str = "A")` behaves the same), and the same
def **without** the default is correct:

```python
def f(a):
    return a
print(f("z"))     # z — correct
```

So it is the DEFAULT that breaks the parameter, not the string, and not the
return.

## Two distinguishable halves

1. **The written argument.** `f("z")` — an explicit string to a parameter that
   has a default — comes back empty. A NilPy unannotated parameter is
   `tyVariant`, passed by reference; something on the has-default path passes
   the string handle rather than a variant slot.

2. **The filled default.** `f()` reaches the IR default-fill
   (`ir.inc:7449`), which knows two shapes: `tyAnsiString` (materialised into a
   hidden managed temp) and everything else (the raw frozen literal). A
   `tyVariant` parameter gets the raw literal, so the callee dereferences a
   string handle as a variant. Visible directly:

   ```python
   def f(a="A"):
       return len(a)
   print(f())    # TypeError: expected a str, list, dict or bytes, got int
   ```

   The int it reports is the unboxed literal.

Integer defaults are fine in both halves (`def f(a=1): return a + 1` → 6/2),
which is why this survived: the default machinery works, only its variant/string
combination does not.

## Where it bites

songformatter writes string defaults everywhere (`def textOut(self, text="")`,
`def setFont(self, name, size, leading=None)`), so this is on the path between
`convertrawtext.py` COMPILING (it does, as of this commit) and RUNNING.

## Gate

`make test-nilpy` plus the four shapes above diffed against CPython — written
arg and filled default, string and int, annotated and not.

Note for whoever takes it: `pyvar_of_str` (pylib) and `PyBoxStrNode`
(`parser.inc`) were added for the by-hand call path and box a string literal
into a Variant; the IR default-fill needs the same thing, or an `IR_VAR_BOX`.
