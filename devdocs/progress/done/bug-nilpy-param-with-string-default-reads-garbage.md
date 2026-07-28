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

Integer defaults are no better once the default is actually FILLED: any omitted
argument crashes, whatever its type —

```python
def summed(a, b=2, c=3):
    return a + b + c
print(summed(10, 20, 30))   # 60  — every argument written, fine
print(summed(10, 20))       # CPython 33; pxx SEGFAULTS
```

— because `DefaultArgValueNode` passes `pynone()` for a variant parameter (a
NilPy parameter is by-reference, so the raw ordinal cannot be handed over) and
the IR fill (`ir.inc:7449`) passes the raw literal. So the honest summary is:
**a NilPy def's declared default is never the value the callee sees.** Written
arguments are correct; the machinery only fails where it has to MATERIALISE one.

Boxing was tried and does not reach: `pyvar_of_int`/`pyvar_of_str` produce an
rvalue, which has no address for a by-reference parameter, and a hoisted variant
temp put the store outside the expression that needed it. The likely shape of
the fix is a hidden variant local per defaulted parameter, initialised in the
CALLEE's prologue when the caller signals the argument was omitted — i.e. the
default belongs to the callee, not to every call site.

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

## Log
- 2026-07-28 — resolved, commit 13a8e4213.

## Resolution

Fixed by 13a8e4213 ("fix(nilpy): a declared default is what the callee actually
runs with"), which moved the default fill to the CALLEE — the shape this ticket
predicted — and added `test/test_nilpy_default_arguments.npy`. The ticket was
left in `backlog/` by that commit.

Re-verified 2026-07-28 on the exact repros above: `f("z")`/`f()` print `z`/`A`,
`len(a)` on a filled string default is `1`, and `summed(10, 20)` is `33`. All
match CPython.
