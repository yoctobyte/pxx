---
slug: bug-p-a-conditional-directive-cannot-read-a-constant-or-a-type-the-source-declares
title: "`{$if}` cannot read a constant or a type alias the source declares"
track: P
prio: 60
type: bug
status: open
owner: ""
found-by: frankH
created: 2026-09-09
tags: [conditional-directives, lexer, fpc-corpus]
blocked-by: []
summary: "`{$if MAXOPS > 2}` where `MAXOPS` is a source-level `const`, and `{$if sizeof(TBig) = 8}` where `TBig` is a source-level type ALIAS, are both refused -- in the same file and through a `uses` clause alike. fpc compiles all four. This is the SECOND-LARGEST blocker of umbrella-pxx-compiles-fpc-itself, 24 of 207 units behind the unit-cycle bug's 144, and the two questions are one mechanism: the `{$if}` evaluator is answered at LEX time and has no door to the declarations. Two doors of exactly the right shape already exist beside it -- PasCondSizeOfTypeName and PasCondNameDeclaredInUses, both forwarded from compiler.pas so the answer stays with the parser -- so this is a third question through the same hatch, not a new architecture."
---

# `{$if}` over a declared constant or type

FPC's scanner and parser are interleaved, so by the time `{$if max_operands>2}`
is scanned the constant is already in the symbol table. pxx lexes a file in its
own pass, so the evaluator sees defines and nothing else.

- **Umbrella:** `umbrella-pxx-compiles-fpc-itself`
- **FPC units and lines:** `aoptutils.pas:34` (`{$if max_operands>2}`,
  `max_operands = 4` at `x86/cpubase.pas:299`), `hlcg2ll.pas:1347`
  (`{$if first_mm_imreg = 0}`, `first_mm_imreg = $20` at `x86/cpubase.pas:173`),
  and eighteen units on `{$if sizeof(bestreal) ...}` where
  `bestreal = extended` at `x86_64/cpuinfo.pas:32`.

## Minimal repro — all four rows, measured 2026-09-09 at 24dbb0b37

```pascal
{ ucfg.pas }
unit ucfg;
interface
const MAXOPS = 4;
type TBig = Double;
implementation
end.
```

```pascal
program m;
uses ucfg;                 { drop the unit and declare both here: same result }
begin
{$if MAXOPS > 2}       WriteLn('a'); {$else} WriteLn('b'); {$endif}
{$if sizeof(TBig) = 8} WriteLn('c'); {$else} WriteLn('d'); {$endif}
end.
```

    pxx, const:  conditional directive: `MAXOPS` has no integer value here
    pxx, sizeof: conditional directive: sizeof cannot size this type here: TBig
    fpc:         compiles, prints `a` then `c`

**The boundary is the DECLARATION, not the unit.** Both rows fail with the
declarations in the same file as the directive, so the used-unit half is not
what is missing; the evaluator has no route to a declaration at all. What DOES
work: `{$if sizeof(Double) = 8}` (a builtin name) and `{$if declared(X)}`
(including for a name in a used unit).

## Where it lives, and why the shape is already decided

`paslexer.inc`'s `EvalPasCondExprText` resolves an identifier through
`PasDefineLookupValue` and then falls back to "is it defined". Two questions
beside it are already answered by the parser side rather than by a table in the
lexer:

- `PasCondSizeOfTypeName` (`pasparser_lval.inc:8862`) -- forwarded so the widths
  stay beside `BuiltinTypeNameTk`, whose own comment records three fixes for a
  second size table drifting. It answers BUILTIN names only; a source-declared
  alias returns -1, which is the `sizeof cannot size this type here` above.
- `PasCondNameDeclaredInUses` (`pasparser_proc.inc`) -- resolves a used unit's
  SOURCE and walks its tokens, with `PasProbeSaveLexState` around it.
  `PasCondNameDeclaredIn` already takes an arbitrary token range for exactly
  this reason.

So the work is a third forwarded question -- "does this name have an integer
constant value" -- plus teaching `PasCondSizeOfTypeName` to follow one level of
`type A = B` before giving up, both reusing the walk and the probe that exist.
**Not verified**: whoever takes this should confirm the walk can see a `const`
value (it currently records only that a name IS declared, not what it equals).

## What must NOT be widened

The `sizeof` arm's own comment is the constraint: *"A NAME THIS DOOR CANNOT SIZE
IS A DIAGNOSTIC, NOT A DEFAULT"* -- records and frozen strings have no layout
during LexAll, and answering 0 or a pointer width picks a branch silently. A
conditional that takes the wrong arm does not produce a wrong value, it produces
a different program. Same for the const half: a name whose value is an
EXPRESSION rather than a literal should keep the current error rather than be
guessed at.

## Why prio 60

From the corpus, not from the backlog: 24 of 207 units of FPC's compiler stop
here, second only to
[[bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface]]
at 144. Both numbers are first-failure counts and therefore lower bounds --
a unit that stops on the cycle may stop here next.
