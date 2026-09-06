---
prio: 70
track: P
status: done
owner: frankD
summary: "A bare own name inside a nested FUNCTION THAT CAPTURES something was compiled as a recursive CALL with the hidden capture actuals spliced in, instead of as a read of the result var. `if F >= 0` became `F$21(Top)` against `F$21(Top; out R)` -- an arity error naming `F$<n>`, an identifier the programmer never wrote, attributed to `./compiler/builtin/builtinheap.pas`. THE ARITY ERROR IS THE LUCKY FACE. When the nested function is PARAMLESS the spliced call is well-formed -- `F(Top)` matches `F(Top)` exactly -- so it COMPILED CLEAN AND RECURSED FOREVER: a 10-line program where fpc prints 6 and we SEGFAULT with no diagnostic at all. A trailing `.field` or `[i]` on the own name is the same silent shape. Arity is what made one face visible and arity is an accident of the repro. Fixed in `compiler/pasparser_decl.inc` (ParseNestedRoutine): the own-name rewrite split occurrences TWO ways -- followed by `:=` is a result write, everything else is a recursive call -- and a bare READ is a THIRD reading it did not have. Now the splice needs `(` after the name, except for a nested PROCEDURE (bare own name is unambiguously a call) and {$mode delphi} (a bare own-name read is a routine reference, mirroring pasparser_expr.inc's `not DelphiMode` guard). NOT the `pparser.pp:2670 PeekOper` wall -- that is a SIBLING call and is still open; this was found while reducing it and my reduction had silently drifted onto a different defect."
---

## The three faces, measured

Compiler before: `48c9f5942757` at `72b9578d5`. After: `8b10e02e2029`.
Independently reproduced under pin v407 (`095ef4811a5b`), so it is not a
local-tree artefact. fpc 3.2.2 is the oracle on every row.

| shape | before | after | fpc |
| --- | --- | --- | --- |
| captures + own params, `if F >= 0` | **compile error**, `no overload of F$21` | `5 1` | `5 1` |
| captures (dyn array) + own params | **compile error**, `no overload of F$27` | `3 1` | `3 1` |
| captures, **PARAMLESS**, `if F >= 0` | **compiles, SIGSEGV** | `6` | `6` |
| captures, `F.Row := Base` | **compiles, SIGSEGV** | `row = 42` | `row = 42` |
| no captures + own params | ok | ok | ok |
| non-nested, top level | ok | ok | ok |
| nested PROCEDURE, bare `P;` | ok | ok | ok |
| capturing fn, explicit `F()` | ok | ok | ok |
| `{$mode delphi}`, bare own name | ok | ok | ok |

The loud row prints

```
pascal26:9: error: no overload of F$21 matches these arguments
  argument types: (Integer)
  candidates:
    F$21(Integer, record)
  in: ./compiler/builtin/builtinheap.pas
  note: that unit is appended to every program by the compiler -- you did not write it.
```

`(Integer)` is the spliced capture with the routine's own parameters gone,
because a bare read has none by construction. **Both halves of that message
point away from the source**: `F$21` is a name the program does not contain,
and the `in:` line accuses a unit the programmer did not write and the note
then says so, which reads as "the compiler's own header is broken" rather than
"line 9 of your file".

## Mechanism

`ParseNestedRoutine` (`compiler/pasparser_decl.inc`) lifts a nested routine to
top level and rewrites body references to its own name, mangling `F` to
`F$<n>`. A capturing routine gains hidden leading parameters, so a
self-reference that is a CALL must gain the matching actuals — that arm was
added by `bug-nested-proc-sibling-call-unresolved` symptom 2 and is correct.

The discriminator it used was **"followed by `:=`"**: a result write if yes, a
recursive call if no. There is a third reading, and it is the one the flip in
`pasparser_expr.inc` had already established everywhere else — in
objfpc/default a bare own-name VALUE READ is the result var. It is not followed
by `:=`, so it took the call arm.

The two passes then could not correct each other. `pasparser_expr.inc`'s
own-name-read branch is guarded `Tokens[TokPos].Kind <> tkLParen`, and by the
time it runs the hoist pass has already inserted `(Top)` — so the branch that
knows the right answer excludes itself on the evidence the wrong pass planted.

## Why the silent face is the bigger one

The arity error only exists because the routine has parameters of its own. A
paramless capturing nested function gets `F(Top)` spliced onto a signature that
is exactly `F(Top)` — a well-formed, correct-arity, infinitely recursive call.
`test_nested_fn_bare_own_name_read.pas` therefore asserts VALUES on every row;
a compiles/does-not-compile row passes on the version that segfaults.

**[[a-guard-that-cannot-fail-is-not-a-guard]] in its assertion-class form**: the
population here is "nested functions that capture", and within it the refusing
member is the one with parameters. A corpus finds that one and says nothing
about the other, which is the same silent/refused asymmetry
[[feature-pascal-corpus-expansion]] recorded for the set-literal wall.

## What this narrows, deliberately

Inside a CAPTURING nested function, statement-position `F;` no longer
self-recurses — write `F()`. That is not a new rule, it is the existing one
reaching here: the paramless flip
(`bug-bare-function-name-call-vs-resultvar`) already made `F()` the spelling for
self-recursion everywhere else and a nested routine was silently exempt.
Measured: **fpc refuses that spelling outright** (`Illegal expression`), so no
fpc-compatible source loses anything. Nested PROCEDURES and `{$mode delphi}`
keep the old behaviour and both have a control row.

## How it was found, and the correction that matters

Reducing the `pparser.pp:2670 PeekOper` wall. The reduction `n1.pas` was
recorded as reproducing that wall; it was reproducing THIS one. Both print `no
overload of <name>$<n> matches these arguments` with a mangled name and a
capture-shaped candidate list, and the wall's own construct (`Result:=PeekOper`,
a SIBLING call) is one token away from the shape that reproduces. **The
reduction had drifted onto a different defect and the error message could not
tell me** — n1 compiles and matches fpc now, and `pparser.pp:2670` is
unchanged.

The discriminator that separated them, once I stopped varying the enclosing
scope: writing the same body with `Result :=` instead of the own name. That row
is kept in the fixture for exactly that reason.

## Log

- `compiler/pasparser_decl.inc` — the third arm, with the mode/kind carve-out.
- `test/test_nested_fn_bare_own_name_read.pas` + `.expected` — 8 rows, faces and
  controls; `.expected` is fpc 3.2.2's own output.
- `test/test_nested_fn_bare_own_name_delphi.pas` + `.expected` — the mode arm.
- `Makefile` — two `test-core` rows (`test_nestown26`, `test_nestowndel26`).
