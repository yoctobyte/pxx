---
slug: bug-p-a-for-in-container-must-start-with-an-identifier-token
track: P
prio: 40
type: bug
blocked-by: []
status: done
owner: frankS
created: 2026-09-07
found-by: frankS
summary: "FIXED 2026-09-08. The gate was one line — `if CurTok.Kind <> tkIdent then Error(...)` at pasparser_stmt.inc:3287 — and it never described the container: `for i in (v)`, `for i in 4` and `for i in Integer(4)` were refused while `for i in Int64(4)` compiled, because Int64 lexes as tkIdent and Integer does not. WHAT IT WAS PROTECTING, established before removing it as this ticket asked: the 128 lines below it are seven arms that each read CurTok.SVal (FindSym, FindProc, FindTypeAlias, FindSetConst, FindUField) or the selector token after the name, and none of them means anything for a non-identifier. So the gate is not deleted — it becomes the PRECONDITION on that block, and what falls through reaches the general container-EXPRESSION path below, which is where those spellings were always going to be decided. All five of this ticket's rows now match fpc 3.2.2. RESIDUAL, measured and NOT this defect: with the operator declared only on Int64, `for i in Integer(4)` is still refused, because FindOpOverload matches (opKind, typeKind, recId) EXACTLY while fpc picks the Int64 overload by assignment compatibility — and symtab.inc already has the ranked ladder for it (OpConvSourceRank), used by conversion operators and not by this lookup. Recorded on the precedence ticket, which needs a ranked lookup anyway."
---

# A for-in container must start with an identifier token

`compiler/pasparser_stmt.inc:3087`:

```pascal
if CurTok.Kind <> tkIdent then
  Error('for-in: expected a generator, enum type, or iterable variable');
```

Measured 2026-09-07 at compiler `029799e446d5`, with
`operator enumerator(a: Int64): TEnum` in scope, against fpc 3.2.2:

| container | pxx | fpc |
| --- | --- | --- |
| `v` (Int64 variable) | 9 | 9 |
| `Int64(4)` | 4 | 4 |
| `Integer(4)` | **refused** | 4 |
| `4` | **refused** | 4 |
| `(v)` | **refused** | 9 |

**The tell is that `Int64(4)` works and `Integer(4)` does not.** Same construct,
same operator, same value — the only difference is that `Int64` reaches the
parser as `tkIdent` and `Integer` as its own token kind. Nothing about the
container's meaning is being consulted; the gate is reading the lexer.

## Why it is probably small

The gate guards a dispatch that already ends in a general container-EXPRESSION
path (dyn-array value, string value, set-valued call, and since 2026-09-07 any
value whose type has an `operator enumerator`). Every shape in the table above
is something that path can already decide — they are refused before reaching it,
not after failing in it. The `(v)` row is the clean demonstration: `v` alone
compiles, and one pair of parentheses is the entire difference.

## What to check before removing it

The gate predates the expression path and may be carrying a real
disambiguation — `for` has a counted form too, and `for i := 1 to 4` must not be
mistaken for a container. Establish what it was protecting before deleting it
rather than after: if the answer is "nothing any more", say so in the commit,
because a one-line deletion with no recorded reason is what makes the next
reader restore it.

## Re-ranked 30 -> 40 (frankS, 2026-09-07, on frank-coord-core's argument)

Filed at 30 on volume -- little real code writes `for i in (v)`. The better axis
is that **the discriminator is a lexical accident, so the observable is
ARBITRARY rather than merely wrong**: `Int64(4)` compiles and `Integer(4)` does
not, for no reason visible in the source, so a user cannot form a rule from it
and cannot predict which spelling of their own cast will build. That is worth
more than its frequency.

Not higher than 40, for the reason CLAUDE.md gives for ranking loud above
silent: this refuses to build, so nobody gets a wrong answer from it, and the
workaround is to name the value. Its sibling
[[bug-p-for-in-over-a-string-prefers-a-user-operator-enumerator-and-fpc-prefers-the-builtin]]
stays the one to take first -- that one is silent.

**Kept as `type: bug`, not `compat`.** CLAUDE.md files "FPC accepts a form we
reject" as compat, and this qualifies on its face. But the finding is not that
we lack a dialect feature -- we HAVE this one, and accept it through one
spelling while refusing an equivalent one. The inconsistency is inside our own
rule, which is a bug in it.

Found while fixing
`test/test_for_in_operator_enumerator_on_an_alias_and_an_expression.pas`, whose
row 4 uses `Int64(4)` precisely because `Integer(4)` does not compile.


# Fix (2026-09-08, frankS)

The gate is now the block's precondition rather than a refusal:

```pascal
    if CurTok.Kind = tkIdent then
    begin
      ...the seven ident-only arms, unchanged...
    end;
    { general container EXPRESSION path — takes what falls through }
    ParseExpr;
```

**What it was protecting, since this ticket asked that it be established BEFORE
the change and not after.** Every arm between the gate and the expression path
reads `CurTok.SVal` — `FindSym`, `FindProc` (generator), `FindTypeAlias` (named
subrange), `FindSetConst`, `FindUField` (implicit-Self field) — or the selector
token that follows the name. None of them has a meaning for a non-identifier, so
the gate was a real precondition wearing the shape of a diagnostic. Saying so
here because a one-line deletion with no recorded reason is what makes the next
reader restore it.

It was not carrying the counted-for disambiguation the ticket wondered about:
`for i := 1 to 4` is decided further down by `Expect(tkAssign, ':=')`, past the
whole for-in dispatch, and the `illegal counter variable` check sits below that.

## Rows, all against fpc 3.2.2

`test/test_for_in_operator_enumerator_on_an_alias_and_an_expression.pas`
gains three rows and is byte-identical to fpc at 8/8:

| container | before | after |
| --- | --- | --- |
| `Int64(4)` | 1004 | 1004 (control — the spelling that always worked) |
| `Integer(4)` | refused at the gate | 4 |
| `4` | refused at the gate | 4 |
| `(vv)` | refused at the gate | 9 |

`cast` and `castint` are the pair that matters: the SAME cast, differing only in
a token kind, and they now agree with fpc while answering DIFFERENT numbers
(1004 vs 4) — so the operator table is answering on its key rather than
ignoring it. A one-row table cannot tell a correct lookup from a lookup that
ignores its key, and neither can two rows that return the same value.

Positive control on the pre-change compiler: `pascal26:73: error: for-in:
expected a generator, enum type, or iterable variable`.

## Residual, measured, and NOT this defect

With the operator declared **only** on `Int64`, `for i in Integer(4)` is still
refused — now by the expression path (`not a generator, enum type, or iterable
variable`) rather than by the gate. fpc takes the `Int64` overload for an
`Integer` operand by assignment compatibility; `FindOpOverload` matches
`(opKind, typeKind, recId)` **exactly**.

That is not a missing rule so much as an unused one: `symtab.inc` already holds
`OpConvSourceRank`, whose header records fpc's measured ladder ("exact kind,
else same SIGNEDNESS, else any integer") — and it is consulted by CONVERSION
operators and not by this lookup. Recorded on
[[bug-p-for-in-over-a-string-prefers-a-user-operator-enumerator-and-fpc-prefers-the-builtin]],
which has to grow a ranked lookup anyway and should grow one ranked lookup
rather than two.
