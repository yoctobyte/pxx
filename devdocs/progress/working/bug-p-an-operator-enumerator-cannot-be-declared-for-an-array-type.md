---
slug: bug-p-an-operator-enumerator-cannot-be-declared-for-an-array-type
track: P
prio: 30
type: bug
blocked-by: [bug-p-a-distinct-type-declaration-is-parsed-but-is-not-distinct]
status: working
owner: frankS
created: 2026-09-08
found-by: frankS
summary: "`operator enumerator(a: TDyn): TEnum` and the static-array form are refused at the DECLARATION with `operator overloading: <T> is not a supported operand type`. fpc 3.2.2 accepts both and runs them in preference to its own built-in array iteration. RE-SCOPED 2026-09-08, twice over, both corrections downward. (1) It is NOT a missing entry in an accepted set: the Ovrl table carries three columns — OpKind, TypeKind, RecId — an array type has no RecId, so an array operand can only key on its ELEMENT kind and collapses onto the row for that scalar. That is the identical collapse tforin15 is skipped for, whose reason ends `do not half-plumb it`, and the use site cannot supply an array identity either: no AST node carries an ArrType row, so the expression spelling could not be keyed even if the declaration were. Same channel as bug-p-a-distinct-type-declaration-is-parsed-but-is-not-distinct, extended to operators. (2) It does NOT block the for-in precedence work, and this ticket said it did. Those two families have exactly ONE enumerator candidate in pxx, so a precedence RULE is vacuous there rather than untested — what is unmeasurable is the array arm, not the rule."
---

# `operator enumerator` on an array type is refused at the declaration

Measured 2026-09-08, compiler `b2361e541c4b`, fpc 3.2.2 `-Mobjfpc`.

```pascal
type
  TDyn  = array of Integer;
  TStat = array[0..1] of Integer;
operator enumerator(a: TDyn): TEnum;  begin ... end;   { pxx: refused }
operator enumerator(a: TStat): TEnum; begin ... end;   { pxx: refused }
```

```
pascal26:15: error: operator overloading: TDyn is not a supported operand type
pascal26:18: error: operator overloading: TStat is not a supported operand type
```

fpc accepts both, and `for i in <that array>` then runs the OPERATOR rather
than the built-in element iteration — `55` and `77`, the operators' own
constants, not `5 6`.

# Why it is worth more than its volume

It is loud, so nobody gets a wrong answer from it. It ranks because of what it
does to the INSTRUMENT: `enumerator` is the one operator whose whole purpose is
to give a type an iteration meaning, and the two array families are exactly
where a container library would want one. While the declaration is refused,
`for i in <array>` can only ever take the built-in path in pxx, so the
precedence question its sibling ticket is about is not merely unanswered for
arrays — it is unaskable, and a rule written to cover all families would land
with two of them untested.

# Where

`compiler/pasparser_call.inc:573` gates which operand types an operator may be
declared for; `OPK_ENUMERATOR` is listed there beside `OPK_INC`/`OPK_DEC` as
one of the unary-ish keys. The refusal text is the general
`operator overloading: <T> is not a supported operand type`, so the array kinds
are simply absent from the accepted set rather than refused by an arm that
mentions enumerators.

Check whether the same gate refuses a `record` and a `set` operand — the set
form IS accepted today (measured, `operator enumerator(a: TSet)` compiles), so
the accepted set is not simply "scalars".


## Re-scoped 2026-09-08 (frankS) — twice, both corrections downward

**It is not a missing entry in an accepted set.** `defs.inc` gives the operator
table three columns — `OvrlOpKind`, `OvrlTypeKind`, `OvrlRecId` — and an array
type has no rec id. So an array operand could only be keyed on its ELEMENT kind,
and `operator enumerator(a: TDyn)` with `TDyn = array of Integer` would register
under `(tyInteger, REC_NONE)`: **the same row as `operator enumerator(a:
Integer)`**, first declared winning.

That is not a hypothesis about a new column; it is the collapse the tree already
has and already documents. `tforin15.pp` is skipped for exactly it — `Twice` and
`Integer` under one key, pxx printing 1 where fpc prints 2 — and its reason ends
*"Burning this row needs alias IDENTITY in the operator table AND at the use
site… Do not half-plumb it; that ticket settled that a channel which guesses is
worse than one that abstains."* `OperandTypeKindRec`'s own header says the same
in the paragraph immediately above the refusal this ticket quotes, and names
`tarray18` as the array case staying a gap.

**The use site cannot supply the identity either**, which is what makes this
larger than the declaration. A symbol container can recover its array row
(`FindArrayType` over `SymDeclTypeNOff`, as `pasparser_expr.inc:4752` does), but
no AST node carries one — so the EXPRESSION spelling would still key on the
element kind and the two spellings would disagree. Wiring only the declaration
is the half-plumbing both prior tickets refuse.

So this is `blocked-by`
[[bug-p-a-distinct-type-declaration-is-parsed-but-is-not-distinct]] — the same
channel, extended to operators — and re-ranked 35 -> 30, because it is one more
consumer of a channel that does not exist rather than a standalone fix.

## And it does not block the precedence work — this ticket said it did

The summary originally argued that two of the five container families are
unmeasurable and therefore *"any precedence rule written for them today would
land with two arms untested"*. **That is the wrong reading of what those two
families are.** With the operator declaration refused, an array container in pxx
has exactly ONE enumerator candidate — the built-in. A rule that RANKS candidates
has nothing to rank there. It is not untested; it is vacuous, and it stays
vacuous until this ticket is burned.

What is genuinely unmeasurable is this ticket's own arm, not the rule. Recorded
because the original phrasing would have held up
[[bug-p-for-in-over-a-string-prefers-a-user-operator-enumerator-and-fpc-prefers-the-builtin]]
behind a blocker that is not one, and I wrote it.
