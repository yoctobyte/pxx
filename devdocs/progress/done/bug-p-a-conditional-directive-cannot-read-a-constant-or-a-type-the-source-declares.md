---
slug: bug-p-a-conditional-directive-cannot-read-a-constant-or-a-type-the-source-declares
title: "`{$if}` cannot read a constant or a type alias the source declares"
track: P
prio: 60
type: bug
status: done
owner: ""
found-by: frankH
created: 2026-09-09
tags: [conditional-directives, lexer, fpc-corpus]
blocked-by: []
summary: "RESOLVED 2026-09-09 (abc681636 + fcbe280b7). `{$if MAXOPS > 2}` over a source-level `const` and `{$if sizeof(TBig) = 8}` over a source-level type ALIAS both work now, in the file that declares them and through a `uses` clause. Fixture test_p_a_conditional_directive_can_read_a_source_const.pas is 23 rows BYTE-IDENTICAL to fpc 3.2.2, every value row paired with a mirror row that must take the other arm, and the PIN refuses the file on its first row. Corpus: the conditional-directive family of umbrella-pxx-compiles-fpc-itself went from 26 of 207 units to 3 -- attributed per unit, the first commit moved exactly 25 rows and every one was in this family. NO UNIT NEWLY COMPILES: everything behind these rows queues on the unit-cycle bug. The residual 3 (set membership over a set-valued const; a const whose value is a folded call) is bug-p-a-conditional-directive-cannot-read-a-const-whose-value-is-not-an-integer-literal, and it is the constraint THIS ticket set being kept, not a regression."
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

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 4d83bc2ca.

## Resolved 2026-09-09, frankH — abc681636 + fcbe280b7

**Both halves work and are fpc-verified.** A source-level `const` is readable
by `{$if}` in the file that declares it and through a `uses` clause, and
`sizeof` follows a type ALIAS up to eight hops before giving up. Fixture:
`test/test_p_a_conditional_directive_can_read_a_source_const.pas` +
`test/condsrc_unit.pas`, 23 rows, **byte-identical to fpc 3.2.2**, and the
PIN refuses the file on its first row.

`PasCondNameDeclaredInUses` became `PasCondProbeUsedUnits(nm, arity, question)`
with `PCQ_DECLARED` / `PCQ_CONSTINT` / `PCQ_TYPEALIAS` dispatched inside the
walk — generalised rather than copied, because the WALK is the subtle half
(`ResolveUsesUnitSource` rather than a Pascal-only file search, the
`ProbeDepth` guard, the per-unit reset to the command-line define baseline)
and none of it differs by question.

**The constraint this ticket set was kept.** A name the `sizeof` door still
cannot size is a diagnostic, not a default; a const whose value is not an
integer literal keeps the old error. The two shapes FPC's compiler actually
asks for there are filed as
[[bug-p-a-conditional-directive-cannot-read-a-const-whose-value-is-not-an-integer-literal]]
(3 units: set membership over a set-valued const, and `high(T)` as a const
value).

**Corpus, per-unit diff both times** (`tools/fpc_compiler_corpus_probe.sh`,
fpc as the oracle): the family went **26 units of 207 to 3**. On the first
commit exactly 25 rows moved and every one of them was in this family; on the
second, 12 more moved and `ALU not defined` (5) and `unterminated conditional
directive` (1) cleared. **No unit newly compiles** — 9 of 207 before and after
— because everything behind these rows queues on
[[bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface]].

**Two probe defects were found underneath and fixed in `fcbe280b7`**, both
predating this work: a probe launched inside a conditional re-lexed the file
it was inside (it scans the whole token stream for `uses` and finds the
parent's `uses <thisunit>`) and unbalanced the `{$if}` stack; and the probe
never expanded the probed unit's `{$I}` includes, so `PUint = qword` — inside
`{$ifdef cpu64bitaddr}`, a define `fpcdefs.inc` sets — was invisible.
`{$if declared(X)}` had both.

**Gate:** quick GREEN on each commit, and the FULL tier was run for the pair
because this touches the conditional evaluator and the lexer's probe
re-entrancy, which every file goes through — quick cannot bound that.
**`gate: GREEN (exit 0)` at `ab1d60ab8`, 23 rows, 0 FAIL**, including
`make test` (2008s) and `make test-nilpy` (2100s).

The first attempt at that tier went RED, and **the red was not this change**:
`9b0c07c2d` had grown `test/c_vla.c` by a row and updated the x86-64
expectation beside it while the three CROSS copies of the same string still
said what the file used to print. Fixed in `8cbe22841` after checking all
three targets already print the new row correctly, so it was a stale
expectation and not a codegen gap. Recorded here because "my change went RED
on the tier" is the reading that terminates the search, and the discriminator
was one `git log -S` on the expected string.
