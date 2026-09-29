---
track: N
prio: 30
type: bug
blocked-by: []
status: done
found-by: frankD (2026-09-29, while fixing bug-n-semicolon-separated-statements-fail-at-an-imported-modules-top-level); routed by frankuser
tags: [nilpy, parser, class, lexer]
summary: "In a class body, `k = 1; j = 2` registered only `k`, so `P.j` failed with `class method not found: j`. A method alias after a ';' (`__rmul__ = __mul__; tag = 't'`) failed with `undefined variable (__mul__)`. A class body is read by token-level scanners as well as its parser. The member pre-pass registers an attribute only at the start of a line and skips to the next NEWLINE, so everything after the first ';' was lost. The lexer now turns such a ';' into a NEWLINE, once, for every reader."
owner: ""
---

# ';'-separated class attributes lose all but the first

```python
class P:
    k = 1; j = 2
print(P.j)        # CPython: 2    Nil Python: class method not found: j
```

## Cause and fix

The three statement loops (the program loop, PyParseBlock, and the module loop)
all consume `;`. A class body is different, because PyRegisterClassMembers
reads it at the token level first. Every attribute, alias and annotation branch
there requires the name to open a line, and every one then skips to the next
NEWLINE. Fixing only the class parser would have left the pre-pass
disagreeing with it.

So the shape is normalised in the lexer, the way the one-line `def`/`class`
suite already is. `PyClassBodySemicolons` runs after each lex and applies to
lines that are:

- inside a class body, at the body's own indentation;
- opened by a name or a string (and not by `with`, `async` or `match`).

On those lines, a `;` outside brackets becomes a NEWLINE token. A one-line
`def f(self): a; b` is untouched, because the lexer has already made it an
indented suite one level deeper, where the `;` belongs to the def.

## Measured (2026-09-29, fixedpoint 8edde2f6b68a)

- `test/test_nilpy_semicolons_in_a_class_body.npy` covers:
  - plain, string, list and annotated attributes, and a trailing `;`;
  - a method alias after a `;`;
  - a one-line class;
  - a one-line def, and `;` in a method body;
  - a subclass that overrides one attribute.

  It equals CPython on x86-64, i386, riscv32 and wasm32. The previous
  compiler refuses it on all four. The rows are x86-64, i386 and wasm32.
- Scope: none of the 1714 tracked `.py`/`.npy` files has a class-body `;`
  outside a docstring (a docstring is one string token, so this pass never
  sees its text). No existing program's tokens change.
