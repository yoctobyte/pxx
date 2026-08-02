---
track: N
prio: 55
type: bug
---

# A constructor call in an unpacking right-hand side won't parse

- **Type:** bug (NilPy frontend gap — loud) — **Track N**
- **Found:** 2026-08-02, by a differential sweep against the CPython oracle.

## Measured

```python
class A:
    def w(self):
        return "A"

a, b = A(), A()      # error: unexpected token
```

The boundary is sharp, and it is not about arity or about calls in general:

| form | result |
| --- | --- |
| `a = A()` — single assignment | ok |
| `a, b = f(), f()` — FUNCTION calls | ok |
| `a, b, c = f(), f(), f()` | ok |
| `a, b, c = 1, 2, 3` | ok |
| `a, b, c = [1, 2, 3]` | ok |
| `xs = [A(), A()]` then `a, b = xs` | ok |
| **`a, b = A(), A()`** | **unexpected token** |
| **`a, b = A(), 1`** | **unexpected token** |
| **`a, b = 1, A()`** | **unexpected token** |

So: a CONSTRUCTOR call anywhere in an unpacking right-hand side, in any
position, kills the parse — while the same constructor is fine in a single
assignment and fine inside a list literal that is then unpacked.

## Likely cause

Ordinary calls work, so the unpack RHS parser handles calls in general. What is
different about `A()` is that `A` is a CLASS NAME — in the single-assignment
path that is routed to construction, but in the unpack RHS list the name is
presumably taken as a TYPE (a typecast or class reference) and the `(` then
does not fit. `PyIsBuiltinConvName` / the `IsClassType(name)` test in
`pyparser.inc` around the conversion-builtin handling is the neighbourhood to
look at.

Worth confirming by dumping tokens before theorising — the repo's own note is
that a wrong root cause here is easy to reach
(`project_dump_tokens_before_theorising`).

## Why it matters

`a, b = Foo(), Bar()` is ordinary setup code, and the failure is a bare
"unexpected token" that points at the line without saying what is wrong — so it
reads as a syntax error in the user's code rather than a missing feature.

## Gate

A `.npy` diffed against CPython covering a constructor in every RHS position
(first, last, middle, alone), mixed with literals and function calls, a
subclass constructor, and a constructor with arguments — plus the single
assignment and list-then-unpack forms as controls.
