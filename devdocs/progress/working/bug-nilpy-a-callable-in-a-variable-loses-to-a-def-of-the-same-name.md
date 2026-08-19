---
track: N
prio: 70
type: bug
blocked-by: []
commit: PENDING-COMMIT
claimed-by: frankonpiler-an
summary: "A variable holding a callable (a bound method, a lambda) loses to a module-level `def` of the same name: the call silently runs the WRONG function. Top wall of the third-party ladder — one root cause behind 12 of the 38 remaining failures."
status: working
---

# A callable in a variable loses to a `def` of the same name

```python
def f(x):
    return "MOD"

class D:
    def f(self, x):
        return "METH"

def go(o):
    f = o.f          # rebind the name to a bound method
    return f("q")

print(go(D()))       # CPython: METH      pxx: MOD
```

**Silent.** No warning, no error — the wrong function runs and returns a
plausible value. It only becomes loud when the two arities disagree, which is
how it was found:

```
Nil Python: decode has no parameter named 'final'
```

## Why this is the top lever

Measured 2026-08-19 on the third-party ladder (`tools/nilpy_ladder.py`),
compiler binary `2b2374c38f2c7407…` self-hosted at `594bd3c8c`:

```
12  Nil Python: decode has no parameter named 'final'   <-- this bug
 4  missing module: xml_etree_elementtree
 3  Nil Python: unknown base class Mapping
 3  undefined variable (property)
 ...all remaining rows are 2 or 1
```

Twelve files, one root cause, and the next row is a third its size. Every one
of the 12 is blocked transitively by ONE occurrence — `webencodings/__init__.py`
line 219, inside `iter_decode`:

```python
def decode(input, fallback_encoding, errors='replace'):   # module level
    ...
def iter_decode(input, fallback_encoding, errors='replace'):
    decode = decoder.decode                                # <-- local rebinding
    ...
    output = decode(b'', final=True)                       # -> resolves to the MODULE def
```

The module-level `decode` has no `final` parameter, hence the message. Because
`webencodings` is imported by all of tinycss2 and much of html5lib, that single
line is the whole 12.

## The boundary (measured, not reasoned)

| shape | pxx | cpython |
| --- | --- | --- |
| local `f = o.f` shadowing module `def f` | `MOD` | `METH` |
| local `f = lambda x: ...` shadowing module `def f` | `MOD` | `LOCAL` |
| same, local renamed to `g` | `METH` | `METH` |
| module-level `f = o.f` after `def f` | `MOD` | `METH` |

So: **not** about bound methods (a lambda does it too), **not** about function
scope (module level does it too). It is purely the name collision. Rename either
side and it is correct.

## Root cause statement

In CPython a `def` is not a separate namespace — it is a name binding like any
other, and the last binding wins. NilPy resolves a bare-name call against
declared procedures FIRST and only falls back to variables, so a `def` outranks
every later rebinding of that name. This is the `normalise-dont-special-case`
shape: one concept (a name that denotes something callable) served by two
mechanisms, and the second one is the one that stays broken.

Related but distinct — both are the same family, neither is this:
[[bug-implicit-self-method-loses-to-unit-proc]] (a method losing to a unit proc,
Track A/Pascal) and [[bug-nilpy-a-nested-def-shadowed-by-an-outer-name-binds-to-None]]
(the def's VALUE going missing rather than the call misrouting).

## Gate

`make compiler/pascal26` + the probes above diffed against CPython +
`tools/gate.sh quick`.
