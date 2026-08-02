---
track: N
prio: 60
type: bug
---

# One-line `def` and `class` bodies do not parse

- **Type:** bug (NilPy frontend gap — hard compile error) — **Track N**
- **Found:** 2026-08-01, while verifying
  [[bug-nilpy-bitwise-shift-on-class-operand-segfaults]] — whose repro is
  written this way and therefore could not be run as published.

## Repro

```python
def f(): return 5
print(f())
```

```
pascal26:1: error: unexpected token
  near:  f    >>>
```

Same for a class:

```python
class C: pass
```

## What makes it narrow: every OTHER compound statement supports it

Measured, same binary:

| form | result |
| --- | --- |
| `if True: print("x")` | **OK** |
| `for i in [1,2]: print(i)` | **OK** |
| `while x < 2: x += 1` | **OK** |
| `with open(p) as fh: pass` | **OK** |
| `if True: return 7` *inside* a def | **OK** |
| **`def f(): return 5`** | **FAIL** |
| **`class C: pass`** | **FAIL** |

So the suite parser already handles "`:` then a statement on the same line" —
`def` and `class` are the two that don't use it.

## Likely cause

`PyParseDefHeader` is documented as "leaving the cursor just past the `:`
NEWLINE INDENT that opens the body" — i.e. it hard-requires the indented form.
`PyRegisterDefShells` and `PyRegisterClassMembers` also scan for a body `tkIndent`
to find the span, so a one-line body has no INDENT for them to find either.

**Measure before fixing — it is SIX sites, not three**, and two of them are
subtle. Sized 2026-08-01:

1. `PyParseDefHeader` — ends with `Expect(tkNewline); Expect(tkIndent);`, i.e.
   the indented shape is mandatory.
2. `PyParseDef` — takes `bodyStart := TokPos - 1` and parses a block, then a
   DEDENT. `PyParseSuite` already handles BOTH shapes and is what `if`/`for`/
   `while`/`with` use; this should use it too.
3. `PyRegisterDefShells` — walks `while Tokens[j].Kind <> tkIndent` to find the
   body.
4. `PyRegisterClassMembers` — finds the body span the same way.
5. **`PyCollectModuleLocalsAST`'s `blockIsDef` tracking.**
6. **`PyAllocModuleGlobals`'s `inDefStack` tracking.**

5 and 6 are the dangerous pair and are easy to miss. Both decide "is this name
bound inside a def?" purely from INDENT depth — a one-line def body has NO
INDENT, so every name it binds sits at depth 0 and would be harvested as a
MODULE GLOBAL. That is exactly
[[bug-nilpy-def-local-assignment-widens-module-global-to-variant]], which was
fixed on 2026-08-01 by making those two scanners lexically def-aware. Landing
one-line defs without teaching both scanners about them re-opens that bug in a
new shape — silently, since it widens a global to a variant rather than
erroring.

So the fix is not "let the header accept one line"; it is "make the notion of a
def BODY independent of INDENT everywhere it is currently inferred from INDENT".

## Why it matters

`def f(): return x` and `class C: pass` are ordinary Python — `class X: pass` in
particular is the idiomatic empty placeholder and appears constantly in stubs,
exception hierarchies and protocol classes. It is a hard compile error rather
than a miscompile, which is the good case, but it blocks whole files.

## Gate

A `.npy` diffed against CPython covering: one-line `def` with a return, one-line
`def` with a bare call, `class C: pass`, a one-line method inside a normal class
body, an empty exception subclass (`class E(Exception): pass`), and the indented
forms of each still working.

## 2026-08-02 — also in an IMPORTED `.py` module, and the line number lies

Re-sighted from a different direction (verifying imported-module scope for
[[bug-nilpy-identifiers-are-case-insensitive]]), so it is not confined to the
main `.npy`:

```python
# helper.py, imported by a .npy
def get(): return "lower-get"
```

```
Expected: newline, but got:  (Kind: 49, Line: 4)
pascal26:4: error: unexpected token
```

Two things worth keeping when this is fixed:

- The reported line is the **importing** file's numbering, not the module's, so
  the error points at an unrelated line in a file that does not contain the
  construct. That mis-attribution is worth a look on its own — it will make any
  module-level syntax error hard to locate, not just this one.
- Splitting the body onto its own indented line compiles and runs correctly, so
  the module path is otherwise fine.

## 2026-08-02 — the CLASS half is DONE (commit 9e5d2a80a); the def half stays open

`class C: pass` and `class E(Exception): pass` now parse. Only `pass` is accepted
as a one-line class body; anything else is refused with "put the body on its own
indented line".

**Why that restraint is the whole point of splitting here.** This ticket's own
sizing calls out sites 5 and 6 — `PyCollectModuleLocalsAST`'s `blockIsDef` and
`PyAllocModuleGlobals`'s `inDefStack` — as the dangerous pair, because both infer
"is this name bound inside a def?" from INDENT depth, and a one-line def body has
no indent. Land one-line defs without teaching them, and every name such a def
binds is harvested as a MODULE GLOBAL: a silent re-opening of
[[bug-nilpy-def-local-assignment-widens-module-global-to-variant]].

An EMPTY class body reaches neither scanner. It registers no members at all, so
the INDENT-keyed pre-passes have nothing to find, and the change touches sites 1
and 2 only — in the class header, not the def header. That is why `pass` and only
`pass`: a one-line class body with real content would put content back in front
of those scanners for no benefit.

`test/test_nilpy_one_line_class_body.npy` (+ `.expected`, wired into `make
test-nilpy`) checks the result is a REAL class rather than a parse that merely
succeeds — constructible, subclassable, carrying dynamic attributes, and reached
from an ordinary class.

### What is left

The `def` half, in full, and it is still the six-site job described above minus
the class-side pieces:

1. `PyParseDefHeader` — still ends `Expect(tkColon); Expect(tkNewline);
   Expect(tkIndent);`
2. `PyParseDef` — should use `PyParseSuite`, which already handles BOTH shapes
   and is what `if`/`for`/`while`/`with` use
3. `PyRegisterDefShells` — walks to a body `tkIndent`
5. `PyCollectModuleLocalsAST` — `blockIsDef` by indent depth
6. `PyAllocModuleGlobals` — `inDefStack` by indent depth

(4, `PyRegisterClassMembers`, is unaffected by the class change — a one-line
METHOD inside an ordinary class body still needs it.)

### Found while testing this, filed separately

[[bug-nilpy-raise-of-empty-exception-subclass-with-no-args]] — `raise E()` where
`class E(Exception): pass` segfaults or silently skips the `except`. Pre-existing
and reproduces on the indented spelling too, so it is not fallout; but it does
mean the obvious next test to write for one-line classes (an exception hierarchy)
hits a different bug first, which is worth knowing before writing it.
