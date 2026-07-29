---
track: N
prio: 70
type: bug
---

# `cb = handler` then `cb(x)` compiles and does NOTHING

A callable assigned to a **plain local/global name** and then called is a silent
no-op. No diagnostic, no crash — the call simply does not happen.

```python
def hi(x):
    print("hi", x)

g = hi
g(5)            # <- nothing is printed
print("after")  # <- runs
```

Same for a lambda:

```python
g = lambda x: print("got", x)
g(5)            # nothing
```

And the ZERO-argument form does not even parse:

```python
g = lambda: print("plain")
g()             # error: expected expression
```

## What DOES work (so the dispatch itself is fine)

A callable reached through a **subscript** works, because the subscript's result
is typed `tyVariant` and therefore takes the dynamic-call path:

```python
funcs = [hi];  funcs[0](7)      # ok
d = {"a": hi}; d["a"](8)        # ok
f2 = d["a"];   f2(9)            # ok — f2 IS a variant
```

## Where it goes wrong

`ParsePostfix` (parser.inc ~12386) turns `<expr>(` into `PyMakeDynCall` **only
when `ASTTk[CurASTNode] = tyVariant`**. `g = hi` does not give `g` a variant
type:

- `PyMakeFuncValue` (pyparser.inc ~5286) is what boxes a bare def name as a
  Python function object (a `pybound_new` pair, `tyVariant`). It is called from
  ARGUMENT positions and from list literals — not from the assignment
  right-hand side, so `g = hi` parses the name as an ordinary read.
- `PyInferExprType`'s bare-identifier branch has no case for "this name is a
  PROC used as a value", so the inferred local type is not variant either.

Two edits were tried and did NOT fix it (so the real site is a third one — the
plain `NAME = expr` statement path is not the `rhsNode :=` site at pyparser.inc
~9825, which is where the attempt was made): adding `PyMakeFuncValue` to that
RHS branch, and adding a `FindProc(name) >= 0 -> tyVariant` case to
`PyInferExprType`. Find the statement path that actually handles `NAME = expr`
first; expect SIBLING sites (the usual NilPy pattern).

## Already fixed on the way here (do not re-do)

`PyMakeDynCall` now lowers to `pyvar_call0..3` (compiler/builtin/pyeval.pas),
which dispatches on what the variant ACTUALLY holds — bound pair (tag 8),
pyeval closure, lifted bound-fn, or a plain code address. The old lowering was a
raw indirect call on the payload, which is a heap-object pointer for three of
the four shapes. So once `g` is typed variant, the call will dispatch correctly.

## Gate

`make test-nilpy` + self-host fixedpoint, plus the four snippets above matching
CPython.
