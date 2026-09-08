---
slug: bug-p-for-in-over-a-string-prefers-a-user-operator-enumerator-and-fpc-prefers-the-builtin
track: P
prio: 30
type: bug
blocked-by: []
status: done
owner: frankS
created: 2026-09-07
found-by: frankS
summary: "RESOLVED 2026-09-08. With `operator enumerator(a: AnsiString)` in scope, `for ch in s` ran the OPERATOR where fpc 3.2.2 iterates the string's characters — silent, both spellings compiling to a plausible wrong value. The rule is NOT the container's: fpc runs the operator for sets, static and dyn arrays and even over a class's own GetEnumerator, and the SAME container answers differently when only the loop variable's type changes. Measured over five container families and a ten-row width sweep: THE OPERATOR RUNS ONLY WHEN ITS `Current` TYPE IS EXACTLY THE LOOP VARIABLE'S, a container with a built-in meaning otherwise keeps it, and a genuine tie goes to the BUILT-IN. This ticket twice proposed a weaker rule — first `builtin beats operator`, then `rank both, tie to the operator` — and both were drawn from corpora that could not tell them apart from the real one; `for e in st` with the element type as loop variable is the row that separates them, and `Int64` keeping the built-in while `LongInt` does not is the row that rules out a compatibility ladder. Landed as `EnumeratorOpBeatsBuiltin`, read by all three arms including the set's early exit into the membership scan, plus `SameExactTypeKind` naming the Integer/LongInt identity that `MatchParamExact` held the only copy of."
---

# for-in over a string prefers a user `operator enumerator`; fpc prefers the builtin

```pascal
{$mode objfpc}
type TEnum = class
  stop: Boolean; F: Integer;
  function MoveNext: Boolean;
  property Current: Integer read F;
end;
function TEnum.MoveNext: Boolean; begin Result := not stop; stop := True; end;
operator enumerator(a: AnsiString): TEnum;
begin Result := TEnum.Create; Result.F := 99; Result.stop := False; end;
var ch: Char; s1, s2: AnsiString;
begin
  s1 := 'ab'; s2 := 'c';
  for ch in s1 do write(ch, ' ');        writeln;
  for ch in s1 + s2 do write(ch, ' ');   writeln;
end.
```

| container | fpc 3.2.2 | pxx HEAD | pxx PINNED (v407) |
| --- | --- | --- | --- |
| `s1` (variable) | `a b` | `c` | `c` |
| `s1 + s2` (expression) | `a b c` | `c` | `c` |

`c` is `Chr(99)` — the operator's own `F`, read back through a `Char` loop
variable. So it is not a refusal and not a crash: the program compiles and
prints a plausible string.

**It predates the work that found it.** The pinned compiler answers `c` for both
spellings, so this is not fallout from
[[bug-p-for-in-over-a-scalar-expression-never-reaches-the-enumerator-operator]];
that fix made the expression spelling behave like the variable spelling, which
is the normalisation this file's own dispatch asks for, and the shared behaviour
is the one that diverges.

## Why it is worth taking

Iterating a string is the common case and a user operator on `AnsiString` is the
rare one, so the wrong answer lands on the code that did not opt in: declaring
one operator anywhere in a unit silently changes every `for ch in <string>` that
can see it. fpc's rule is the safe one — a type with a built-in iteration meaning
keeps it, and the operator applies where no built-in meaning exists.

## Where, and the trap

`compiler/pasparser_stmt.inc`. Two decision points, and they must move together:

1. The SYMBOL arm (~1396) asks `FindOpOverload(OPK_ENUMERATOR, ...)` for
   `TypeIsFrozenString`/`tyAnsiString` containers **before** falling through to
   string iteration. That order is the bug.
2. The EXPRESSION dispatch (~3300) already runs its string arm before the
   operator arm, i.e. it is already in fpc's order.

So the fix is to the FIRST one — but changing it alone leaves the two arms
agreeing today by accident rather than by rule, and this dispatch's own comments
record twice that two arms deciding independently what a container means is how
one spelling stays broken while its twin works. State the rule once.

**Not measured:** whether the same inversion exists for the other container
families that have a built-in meaning (sets, dyn-arrays). The probe above only
covers strings. Check before writing the rule, because a rule stated for one
family and applied to three is the shape this file keeps warning about.

## 2026-09-08 (frankS) — the rule this ticket proposes is FALSE, measured across five container families

The summary above says *"the rule to adopt is fpc's — a built-in iteration
meaning wins over a user operator on the same type"*. **fpc does not do that.**
It ran the operator on four of the six containers I put in front of it, and the
one thing that decides is not the container type at all.

Compiler `b2361e541c4b`, fpc 3.2.2 `-Mobjfpc`. One `TEnum` with
`property Current: Integer`, one `operator enumerator` per container type, each
returning a distinguishable constant, so the answer says which candidate ran.

| container | loop var | fpc | pxx |
| --- | --- | --- | --- |
| `AnsiString` (symbol) | `Char` | `a b` builtin | `c` operator |
| `AnsiString` (`s1 + s2`) | `Char` | `a b c` builtin | `c` operator |
| `ShortString` | `Char` | `a b` builtin | `B` operator |
| **`AnsiString`** | **`Integer`** | **`99` operator** | **`99` operator** |
| `set of 0..7` (symbol) | `Integer` | `88` operator | `1 2` builtin |
| `set of 0..7` (`st + [4]`) | `Integer` | `88` operator | `88` operator |
| **`set of 0..7`** | **`0..7`** | **`1 2` builtin** | `1 2` builtin |
| `array[0..1] of Integer` | `Integer` | `55` operator | operator decl REFUSED |
| `array of Integer` | `Integer` | `77` operator | operator decl REFUSED |
| class with `GetEnumerator` | `Integer` | `44` operator | `11` GetEnumerator |

### The two bold rows are the whole finding

They are the SAME container type with a different loop variable, and fpc
answers differently. So the choice is not a property of the container and no
per-family precedence table can express it:

> **fpc ranks the candidate enumerators by whether the `Current` type matches the
> LOOP VARIABLE's type, and on a tie the user operator wins over the built-in.**

That one sentence produces every row above. String with a `Char` variable: the
operator's `Current: Integer` does not match, the builtin's `Char` does →
builtin. Same string with an `Integer` variable: now the operator matches and
the builtin's `Char` does not → operator. Set with a `0..7` variable → builtin;
the same set with `Integer` → operator. Array of `Integer` with an `Integer`
variable and a class whose `GetEnumerator.Current` is also `Integer` are both
TIES, and both go to the operator.

**A rule stated for one family and applied to three is what this ticket warned
about, and the ticket's own rule is an instance of it** — drawn from the string
row alone, which is the one row where "builtin wins" and "the loop variable
decides" give the same answer. The probe that separates them is a loop variable
whose type the builtin element cannot fill.

### pxx is inverted in BOTH directions, and its two arms already disagree

Not "pxx prefers the operator": pxx prefers the operator where fpc takes the
builtin (all three string rows) **and** takes the builtin where fpc prefers the
operator (`set-sym`). The set rows also reproduce the two-arms divergence this
ticket predicted, live today — `for i in st` answers `1 2` and `for i in st + [4]`
answers `88`, one program, two spellings.

**The two answers are measured; the mechanism below is READ, not measured.** The
symbol arm (`pasparser_stmt.inc:1593`) asks
`FindOpOverload(OPK_ENUMERATOR, Ord(TypeKind), Syms[contSym].RecName)` for a
non-string container and the expression arm (`:3529`) asks
`FindOpOverload(OPK_ENUMERATOR, ASTTk[forcNode], ResolveNodeRec(forcNode))`, so
the two keys differ in their second component and only the symbol one can miss
on it. That is consistent with what the rows show and is not the same as having
watched the lookup fail — check it with a probe before writing it into the fix.

### Half the rule is already in the tree, in the arm that got it right

`pasparser_stmt.inc:1571` — the class-with-`GetEnumerator` arm — already diverts
to the operator when `GetEnumerator`'s `Current` mismatches the loop variable
and the operator's matches, with a comment recording exactly that reasoning. It
implements one direction of the rule above and stops at a TIE, where it keeps
`GetEnumerator` and fpc takes the operator. **The rule does not need to be
invented; it needs to be lifted out of that arm and stated once for all of
them**, which is what this ticket already asks for and is a bigger change than
its "fix the FIRST one" line suggests.

### Filed alongside, not fixed here, and NOT a blocker

`operator enumerator(a: TStat)` and `operator enumerator(a: TDyn)` are refused
at the DECLARATION — `operator overloading: <T> is not a supported operand
type` — so those two families cannot be measured in pxx at all:
[[bug-p-an-operator-enumerator-cannot-be-declared-for-an-array-type]].

**That does not hold this ticket up, and I first wrote that it did.** With the
declaration refused, an array container in pxx has exactly ONE enumerator
candidate, so a rule that RANKS candidates has nothing to rank there — vacuous
rather than untested. The rule is written and exercised on the families that
genuinely carry two candidates (string, set, class-with-GetEnumerator, scalar
alias); the array families join it when that ticket is burned, and that one is
blocked on an identity channel that does not exist yet.

## A second axis the ranked lookup has to carry (2026-09-08, frankS)

The rule above ranks candidates by the LOOP VARIABLE's type. There is a second
ranking on the container side, and it is also already implemented elsewhere in
the tree:

`FindOpOverload(opKind, typeKind, recId)` matches its key **exactly**. With
`operator enumerator(a: Int64)` in scope and nothing else, `for i in Integer(4)`
is refused; fpc takes the `Int64` overload for an `Integer` operand by
assignment compatibility. Measured 2026-09-08 at compiler `70dffa8a0e51`.

`symtab.inc`'s `OpConvSourceRank` is that ladder — "exact kind, else same
SIGNEDNESS, else any integer", recorded there as fpc's measured answer over five
sources — and it serves CONVERSION operators only.

So whoever writes the precedence rule is writing a ranked selection twice over:
once across candidate KINDS (builtin vs GetEnumerator vs operator, keyed on the
loop variable) and once across candidate OPERANDS within the operator table.
**Grow one ranked lookup, not two**, and take the operand ladder from
`OpConvSourceRank` rather than re-deriving it — its header already carries the
fpc measurement that produced it.

## 2026-09-08 (frankS) — RESOLVED, and the rule is stronger than this ticket proposed

The rule landed is **the operator runs only when its `Current` type is EXACTLY
the loop variable's**; a container that has a built-in meaning otherwise keeps
it, and a genuine tie — neither candidate matching — goes to the **built-in**.

That is not what the revised summary above said. It said "rank both, and on a
tie the user operator wins", and the tie half was **wrong**. It came from the
GetEnumerator row, which was read as a tie and is not one: there both
candidates yield `Integer` and the loop variable IS `Integer`, so the operator
wins by matching exactly. Nothing in the corpus that produced the revision
could tell those two rules apart — every row had at least one exact match.

### The row that separated them, and it was a regression I nearly shipped

`for e in st` with `e: TElem` (`= 0..7`) over `set of TElem`. Under
"tie → operator" it answered the operator; fpc answers the members, `1 2`.
The first landing of the set arm produced exactly that regression, and it was
caught only because the control probe for the set work happened to use the
element type as its loop variable.

### The width sweep is what rules out a ladder

One `set of 0..7`, one `operator enumerator` returning `Current: Integer`, only
the loop variable's declared type moving. fpc 3.2.2:

| `0..7` | `0..15` | `1..3` | Byte | ShortInt | Word | SmallInt | Cardinal | Int64 | LongInt |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `1 2` | `1 2` | `1 2` | `1 2` | `1 2` | `1 2` | `1 2` | `1 2` | `1 2` | **88** |

Nine built-ins and one operator, and the one is `LongInt` — which IS `Integer`,
which is exactly what this operator's `Current` is. **`Int64` losing is the row
that kills a ladder**: it is wider than the element and still keeps the
built-in. Not bounds, not width, not signedness — an exact kind match or the
operator does not run.

So the residual recorded below — "`FindOpOverload` matches its key exactly
while fpc picks by assignment compatibility, and `OpConvSourceRank` already
holds that ladder; grow ONE ranked lookup, not two" — **is not needed for this
axis and would have made it wrong.** A ladder would have handed `Int64` and
`Cardinal` to the operator. The conversion-operator ladder stays where it is,
serving conversion operators.

### `longint` earned its row twice over

`for l in st` with `l: longint` took the built-in where the identical loop
spelled `integer` ran the operator. That is the *closed*
`bug-p-integer-and-longint-are-not-the-same-type-in-overload-matching`
reproducing itself at a second exact-match site: FPC declares one as the
other's alias, and pxx carries them as two kinds (`tyInteger` / `tyInt32`), so
a bare kind comparison discriminates on the SPELLING.

Rather than a second copy of that equivalence, it is now named once —
`SameExactTypeKind` in `symtab.inc` — and `MatchParamExact`, which held the
only copy, routes through it. Two sites is where the rule gets a name.

### Where the ranking had to go for a set, which is not where it looks

A set **returns early** out of `ParseForInVarAST` into the membership scan, so
it was the one container the ranking never reached — `for i in st` answered the
built-in while its expression twin `st + [4]` already answered the operator,
and the two spellings disagreed. The rank therefore happens **at that early
exit**, the last point a set can be ranked at all. The first hypothesis here
was wrong and is recorded because it is the plausible one: that the symbol
arm's `FindOpOverload` missed because it keys on `Syms[contSym].RecName`. It
does not miss; it is never asked.

### Landed

- `EnumeratorOpBeatsBuiltin` (`pasparser_stmt.inc`) — the rule, stated once,
  read by the set early exit, the plain-operator arm and the GetEnumerator arm.
- `SameExactTypeKind` (`symtab.inc`) — Integer/LongInt are one type, named once.
- `test/test_for_in_ranks_the_enumerator_against_the_loop_variable.pas` — 12
  rows, `.expected` derived from fpc, positive control taken by reverting
  (`set-int` and `set-longint` go red at HEAD).

## Log
- 2026-09-08 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 10585d43f.
