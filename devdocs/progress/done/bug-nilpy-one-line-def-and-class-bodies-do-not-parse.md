---
track: N
prio: 60
type: bug
status: done
owner: claude-AN
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

**Correction, same day:** I wrote here that site 4 was unaffected by the class
change. It was not, and the claim cost a shipped bug. `PyRegisterClassFieldsPrepass`
locates a class body by scanning to the first `tkIndent`; a one-line body has
none, so the scan ran on to the NEXT class's indent and registered that class's
members against the one-line class — `class G(Exception): pass` followed by a
class with an `__init__` failed with "unresolved forward: G.create". Fixed in
a0cf42cb6 (stop at the header COLON, read the shape from what follows, and
register an EMPTY member span rather than skipping the pass, which also sizes the
class and emits its VMT).

The reasoning error is worth keeping: "an empty body has no members, so the
member scanners cannot be affected" ignored that a scanner can be wrong about
where the body *ENDS*, not only about what is inside it. The same trap is
waiting for the def half — sites 3, 5 and 6 all locate a def body by INDENT, and
a one-line def body has none.

Site 4 still needs its own work for a one-line METHOD inside an ordinary class
body, which nothing above addresses.

### Found while testing this, filed separately

[[bug-nilpy-raise-of-empty-exception-subclass-with-no-args]] — `raise E()` where
`class E(Exception): pass` segfaults or silently skips the `except`. Pre-existing
and reproduces on the indented spelling too, so it is not fallout; but it does
mean the obvious next test to write for one-line classes (an exception hierarchy)
hits a different bug first, which is worth knowing before writing it.

## 2026-08-04 — the "What is left" list above is STALE; the real residue was the IMPORTED-MODULE half, now fixed

**Read the section above with this correction in front of it.** Its five-site
plan (`PyParseDefHeader` still ends `Expect(tkIndent)`, route `PyParseDef`
through `PyParseSuite`, teach `PyRegisterDefShells` / `PyCollectModuleLocalsAST`
/ `PyAllocModuleGlobals` a second body shape) describes work that was **never
needed and never done**. `a843c17d4` (2026-08-03) solved the def half from the
opposite end and the ticket was never updated.

### What a843c17d4 actually did, and why the site list evaporated

It normalises the one-line suite **in the LEXER**: when a logical line opens with
`def`/`class` and its depth-0 `:` is followed by anything but a comment or the
line end, `PyLexAll` emits `NEWLINE INDENT` after the colon and the owed `DEDENT`
after that line's own newline (`compiler/pylexer.inc:531-550`, `1022-1036`,
`1108-1112`). The `IndentStack` is untouched — the pair opens and closes inside
one physical line.

So the body **has** a real `tkIndent`, and every token-level scanner the ticket
lists sees the shape it already understood. That is this ticket's own demand —
"make the notion of a def BODY independent of INDENT everywhere it is currently
inferred from INDENT" — met by making the INDENT exist rather than by teaching
six consumers to live without it. Sites 1, 2, 3, 5 and 6 need no change, and
site 3's premise is simply false at HEAD: `PyRegisterDefShells` does not walk
`while Tokens[j].Kind <> tkIndent`.

Measured at HEAD before touching anything (`make compiler/pascal26`,
604f30b53 + the fix below): `def f(): return 5`, one-line methods in an
indented class body, chained one-line defs, and a one-line def whose body is a
bare call all match CPython. `def s(): y = 5` then reading `y` at module scope
is reported as a compile-time `undefined variable (y)` where CPython raises
`NameError` at run time — a static-vs-dynamic divergence, **not** the feared
global-harvest: the name is not widened to a module global, which is what sites
5 and 6 were about.

### The one thing that WAS still broken: a one-line def as an imported module's FIRST line

The 2026-08-02 sighting in this ticket (`helper.py`, imported by a `.npy`) was
the live bug, and it was not a second body shape either — it was the lexer rule's
**line-start guard being asked about the wrong stream**:

```pascal
((TokCount = 0) or (Tokens[TokCount - 1].Kind in [tkNewline, tkIndent, tkDedent]))
```

Both clauses are about the WHOLE token stream. `PyLexAppend` lexes an imported
`.py` module **on top of** the importing program's tokens, so at the module's
first token `TokCount` is not 0 and the previous token is the MAIN file's
`tkEOF`. The rule never fired, and the module died on `unexpected token`.

Isolated by measurement rather than reading: the *same* one-line def one line
further down the module compiled and ran correctly. That is what pointed at the
guard instead of at the normalisation.

Fix: `PyLexAll` records `streamBase := TokCount` after the (conditional) reset,
and the guard asks `TokCount = streamBase` — "has THIS lex emitted anything yet",
which is the question that was always meant. It subsumes the old `TokCount = 0`
(the non-appending path resets `TokCount` to 0, so `streamBase` is 0 there).

Verified against CPython: a one-line `def` and a one-line `class` as a module's
first line, a one-line method in a module's indented class body, and the
already-working not-first-line forms as controls.
`test/test_nilpy_one_line_def_in_module.npy` (+ `.expected`, + helper
`test/nilpy_onelinemod.py`), wired into `make test-nilpy`.

### Residue, filed separately rather than carried here

- [[bug-nilpy-one-line-class-body-restraint-is-no-longer-enforced]] — the
  `pass`-only restriction and the comments around it
  (`compiler/pyparser.inc:18948-18977`, `18832-18843`) describe a branch the
  lexer now makes unreachable for `def`/`class`. False comments in this file are
  not cosmetic: they are the interface between passes, and they are what produced
  this ticket's stale five-site plan in the first place.
- [[bug-nilpy-def-body-scans-run-on-when-no-indent-is-found]] — five unguarded
  `while ... <> tkIndent` body hunts that are now protected only by the lexer
  synthesis, plus a producer/consumer divergence in the accepted preceding-token
  set (`tkSemicolon`).

## Log
- 2026-08-04 — resolved, commit PENDING-COMMIT.
