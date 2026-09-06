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

## The narrowing's cost, measured by someone else

**My evidence that nothing used the removed spelling was the self-host
fixedpoint, and that is a claim about `compiler.pas` and `lib/rtl` (a build
input) — not about the tree.** It reads as covering more than it does, which is
the failure mode CLAUDE.md already names for Track P coverage: partial, and
worse than none because it looks total. `lib/pcl`, `examples/`, `test/` and
`tools/` were the residual and I did not measure them.

frankA did, 2026-09-06, unprompted: 2508 `.pas`/`.inc`/`.pp` swept for a nested
`function F` whose own name appears as a bare `F;` — first at line start, then
anywhere on a line (after `then`/`else`/`do`, or beside another statement, which
is where the spelling actually hides). **33 raw hits, zero real ones:**

- `test_nested_routine_depth2_capture.pas` — eleven `C;` sites, every one a
  nested PROCEDURE. Its single nested FUNCTION already writes
  `C := C(n - 1) + n`: explicit parens to recurse, `C :=` for the result. Both
  arms this fix keeps.
- `test_nested_routine_local_shadows_own_name.pas` — five `Inner;` statement
  sites, all nested procedures; its one `function Inner` is read as
  `seen := Inner`, which is the defect fixed here rather than the spelling
  removed.
- The rest: `x := F;` value reads (the fix again), property/type/var noise, and
  `lib/rtl/palthreadobj.pas:463`'s `WaitFor;` — `TThread.Destroy` calling its
  own method, matched only because the first pass could not tell an indented
  method declaration from a nested routine.

**What that census still cannot see, stated because an unlabelled claim beside a
measured one inherits its credibility:** Pascal outside this repo, a name reached
through `with` or a unit qualification, and anything under `compiler/` — which is
exactly where the fixedpoint IS the right instrument. Real outside source using
the spelling is a **compat** item, not a reopening of this call.

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
- All of the above landed together, commit fa7f75bec. `gate.sh quick` GREEN at that
  tree; `make compiler/pascal26` `converged after 1 round(s)`.
