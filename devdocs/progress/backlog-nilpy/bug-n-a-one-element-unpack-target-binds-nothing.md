---
slug: bug-n-a-one-element-unpack-target-binds-nothing
title: A one-element unpack target binds nothing — `(n,) = f()` is "undefined variable (n)"
track: N
type: bug
prio: 45
status: backlog
owner: ""
created: 2026-09-20
found-by: frankH
tags: [nilpy, unpack, assignment, struct]
blocked-by: []
summary: "MECHANISM: the target scan that recognises an unpacking assignment requires TWO OR MORE targets, so a one-element target list is taken for an ordinary parenthesised expression and the name is never bound -- `(n,) = f()` is refused with `undefined variable (n)`. The AXIS IS ARITY, NOT PARENTHESES, and two controls separate them: the bare `a, = f()` fails identically with no parentheses anywhere, and `(b, c) = f()` compiles. CPython binds all three. Reached through the same PyParseUnpackAssign entry as 47841c55b. WHY THE SUITE CANNOT SEE IT: every unpack fixture in this tree has two or more targets, because two is what anyone writing a test for unpacking writes -- the passing arrangement is the population, so the suite certifies the working case. This is CLAUDE.md's 'put the interesting element somewhere other than last' in its ARITY form rather than its ORDER form. NOT EXOTIC: `(n,) = struct.unpack_from(\"<I\", data, 6)` is the idiomatic way to take one field out of a binary header, and it is the only wall in tsp/stars.py."
---

# A one-element unpack target binds nothing

Found 2026-09-20 (frankH) censusing That Space Program under NilPy.
`tsp/stars.py:25` is `(n,) = struct.unpack_from("<I", data, 6)` and is that
file's only wall.

```python
def f():
    return [5]

(n,) = f()      # pxx: undefined variable (n)
print(n)
a, = f()        # pxx: undefined variable (a)  -- no parentheses, same failure
print(a)
(b, c) = [1, 2] # compiles
print(b + c)
```

CPython prints `5`, `5`, `3`.

The two controls are the finding. The reading everyone reaches for first is that
the PARENTHESES confuse the target scan; the bare `a, = f()` spelling rules that
out, and `(b, c) = f()` compiling rules out the other side. What is left is the
element COUNT.

When this is fixed, the fixture must carry BOTH spellings — parenthesised and
bare — because a fix that special-cases the parenthesised form would pass a
fixture written with only that one, and the bare form is the shape that proves
the scan is arity-driven rather than punctuation-driven.
