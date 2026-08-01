---
summary: "s.split(sep)[i] fails IR_UNSUPPORTED when s is a variable, while \"lit\".split(sep)[i] compiles — the frontend loses the result type in subscript position"
type: bug
track: N
prio: 60
---

# `s.split(sep)[i]` on a variable receiver won't lower

- **Type:** bug (Track N, NilPy frontend) — silent frontend gap, hard error
- **Found:** 2026-08-01 by Track T, writing the quick-tier NilPy canary
  ([[feature-t-quick-canary-for-nilpy-and-c]]).

## Repro

```python
s = "Hello,World"
print(s.split(",")[1])
```

```
pascal26: error: IR_UNSUPPORTED: frontend could not lower AST node (kind 8)
          — a frontend gap, would miscompile
```

## What makes it specific

The neighbouring forms all compile and run correctly, which is what makes this a
narrow frontend gap rather than "subscripting calls is unsupported":

| expression | result |
|---|---|
| `s.split(",")` (no subscript) | **OK** — prints `['Hello', 'World']` |
| `"a,b".split(",")[1]` — **literal** receiver | **OK** → `b` |
| `p = s.split(","); p[1]` — two-step | **OK** |
| `g()[1]` where `g()` returns a split result | **OK** → `b` |
| `xs.copy()[0]` — variable receiver, list method returning a list | **OK** |
| `s.upper()[0]` — variable receiver, str method returning a str | **OK** |
| **`s.split(",")[0]` / `[1]` — variable receiver** | **FAIL** |

So it is not "method call then subscript" (that works), not "list-returning
method then subscript" (`xs.copy()[0]` works), and not `split` itself (the
literal receiver works). It is the combination: **a `str`-typed variable
receiver, a method whose result is a list, and an immediate subscript.**

That pattern suggests the frontend knows the result type when the receiver is a
literal or when the value is bound to a name first, but loses it for a variable
receiver in subscript position, leaving an AST node (kind 8) with no lowering.

## Why it matters more than the repro suggests

`parts = line.split(",")` then indexing is the single most common line of
string-handling Python there is, and the one-liner form is what people write
first. It is a hard compile error rather than a miscompile, which is the good
case — but it will be hit constantly.

## Note on the canary

The quick-tier NilPy canary uses the two-step form for this section so it can
land now. That is the documented pattern (file the ticket, keep the code
idiomatic) rather than a workaround hiding the bug — the two-step form is
perfectly ordinary Python and still exercises `split`. Switch it back to the
one-liner when this is fixed; it makes a good regression check.
