---
slug: bug-p-a-property-default-value-clause-is-read-as-the-default-indexed-property-marker
track: P
prio: 50
type: bug
status: done
owner: frankB
created: 2026-09-06
found-by: frankD
blocked-by: []
summary: "`property Depth: Integer read FDepth write FDepth default 16;` sets propIsDefault -- the flag that means THE DEFAULT INDEXED PROPERTY -- because pasparser_decl.inc:5711 handles the two unrelated `default` clauses with one arm. Declared BEFORE a genuine `property Items[i]: ...; default;` it STEALS the slot: `t[2]` is refused with `default property is write-only` where fpc 3.2.2 prints 100. Reverse the declaration order and both print 100, so this is ORDER-DEPENDENT and a probe that happens to declare the indexed property first sees nothing. Separately and in the same clause, only a LITERAL is accepted: `default DefaultDepth`, `default DefaultDepth + 1` and `nodefault` are all refused outright (fpc compiles all three), which is wall 3 of corpus rung 7 -- FPC's pscanner.pp:893 uses the named-constant form. `default 16` alone compiles, but NOT because the literal is consumed correctly -- measured 2026-09-06 by instrumenting the class-body catch-all, the value falls straight through to `pasparser_decl.inc:7230` and is DISCARDED there (frankB's `default 16 77 88 99;` fires it four times, kind=tkInteger, the legitimate 16 included), so the clause has never had any effect; see bug-p-a-class-or-record-body-silently-swallows-any-token-it-does-not-recognise, which must land AFTER this one. Three defects, one arm: the two `default` concepts are conflated, the value is not a constant expression, and `nodefault` is absent."
---

# `default <value>` and `default;` are different clauses sharing one arm

```pascal
property Items[i: Integer]: Integer read GetItem; default;      { THE default indexed property }
property Depth: Integer read FDepth write FDepth default 16;    { an RTTI/streaming default VALUE }
```

Unrelated features, same keyword. `pasparser_decl.inc:5711` is:

```pascal
if CurTok.Kind = tkDefault then
begin
  propIsDefault := True;
  Next;
  Eat(tkSemicolon);
end;
```

— so the value form sets `propIsDefault` too.

## The observable, and it is order-dependent

```pascal
property Depth: Integer read FDepth write FDepth default 16;   { declared FIRST }
property Items[i: Integer]: Integer read GetItem; default;
...
WriteLn(t[2]);     fpc 3.2.2: 100     pxx: error: default property is write-only
```

Swap the two declarations and **both print 100**. So a reader who writes the
indexed property first — which is the natural way to write the example — sees
nothing wrong. Measured both orders.

The diagnostic is the tell even without an indexed property present at all: for
a class whose only `default` is a scalar value clause, `t[0]` gives
`default property is write-only` where fpc gives `No default property
available`. pxx believes a default indexed property EXISTS. Same wrong flag,
visible one step earlier.

## Wall 3 of rung 7: the value must be a constant EXPRESSION

| clause | pxx | fpc 3.2.2 |
| --- | --- | --- |
| `default 16` | compiles (but sets the wrong flag, above) | OK |
| `default DefaultDepth` | **refused**, `expected ':' before ';'` | OK |
| `default DefaultDepth + 1` | **refused** | OK |
| `nodefault` | **refused** | OK |

FPC's `pscanner.pp:893` is
`property MaxIncludeStackDepth: integer read ... default DefaultMaxIncludeStackDepth;`
which is how this was reached.

## Not established

Where the LITERAL is consumed. After `Next` past `default`, `CurTok` is the
number and `Eat(tkSemicolon)` does not take it, yet it never reaches the
class-body loop and a following property parses fine. Find that before adding a
constant-expression parse, or the new code will fight whatever is already
swallowing it.

## Shape of the fix

Split the arm. `default` followed by `;` is the indexed marker and is the only
one that may set `propIsDefault`; `default` followed by anything else is a value
clause and wants a constant expression (`nodefault` is its third spelling).
pxx has no RTTI streaming, so the VALUE itself can be parsed and discarded —
the bug is the flag and the refusal, not the semantics of the default value.

Reached from [[feature-pascal-corpus-expansion]] rung 7. Wall 1 was
`c4036925a`; wall 2 is
[[bug-p-array-of-const-in-a-method-pointer-type-is-refused-and-parsing-it-is-the-trap]].

## 2026-09-06 (frankD) — where the literal goes, measured

The summary previously said the literal *"is consumed somewhere; WHERE is not
established and the stray token does not reach the class-body loop."* Both
halves were wrong, and the correction changes what the fix has to do.

Instrumenting the class-body catch-all (`pasparser_decl.inc:7230`) and compiling
this ticket's own probe at `86f935479`:

```
property Depth: Integer read FX write FX default 16 77 88 99;
   -> 4 x CATCHALL cls kind=2 (tkInteger)
```

Four fires, one per number. The `default` arm at 5711 does `Next` then
`Eat(tkSemicolon)`; `Eat` finds a number, does nothing, and returns. Every
literal is then discarded one at a time by the class-body member loop.

So **`default 16` does not work today** — it compiles because the value is
thrown away, which is exactly what a working-but-ineffective clause looks like
from outside. The fix must PARSE a constant expression here, not merely stop
setting `propIsDefault`; stopping the flag alone leaves the value falling
through the same hole.

Landing order runs the other way from what you might expect: the catch-all
narrowing is blocked-by THIS ticket, because erroring on the stray token before
`default <value>` is parsed would turn legal FPC into a hard error.

## Handover, recorded because it is the fact that goes missing

frankD filed this as rung 7 wall 3 of [[feature-pascal-corpus-expansion]]
(`764dea816`) and therefore held the topic. I reached the same construct from a
P group formed by LANGUAGE FEATURE — property clauses — and claimed it without
checking holdings, which is the collision the roster's *"ask is anyone on this
topic"* exists for and which a board pointer could not have prevented: a pointer
placed on the corpus route is invisible to someone arriving by the feature
route. I offered the diff back; **frankD ceded it explicitly — "Land it. Do not
hand me the diff"** — and stayed on the corpus, holding fcl-passrc wired to run
against the sha. frankD then supplied the measurement that made the fix correct
rather than merely green (see below). Owner is frankB from that point; the wall
stays frankD's.

## Resolution

Split into one shared `ParsePropertyTailDirectives` in `compiler/pasparser_decl.inc`,
called from BOTH branches of `ParsePropertyDecl` — the ordinary one and the
REDECLARATION one, which had written the `default` arm and the hint loop out
twice and carried the same bug in both copies. `default` followed by `;` is the
indexed marker and is now the only spelling that may set `propIsDefault`;
`default` followed by anything else is a VALUE clause and takes a constant
EXPRESSION via `ConstEval`, parsed and discarded (pxx has no RTTI streaming, so
the value has no consumer — the bug was the flag and the refusal, never the
semantics). `nodefault` and `stored` are handled in the same procedure, closing
[[feature-p-a-property-stored-clause-is-not-supported]] with it.

### "Not established" is now established, and by frankD rather than by me

The open question was where the LITERAL went. frankD instrumented the class-body
loop's catch-all `else Next` at `pasparser_decl.inc:7230` and compiled the probe:
`property Depth: Integer read FX write FX default 16 77 88 99;` produced **four
CATCHALL fires, kind=2 (tkInteger), the legitimate 16 included**. The value was
never consumed anywhere — it was thrown away one token at a time by the loop.
So `default 16` "working" was not a clause that parses and has no effect; it was
a clause that does not parse at all, and from outside those are the same.

That matters because it changes what the fix has to do: clearing the flag alone
would have closed this ticket with `default 16` still silently discarding its
operand.

**The discriminator that shows the operand is now OURS**, measured at the fixed
tree rather than argued:

```
default NoSuchConst;   pascal26:5: error: not a constant
                         near: ... write FX default >>> NoSuchConst ; end
default 16 * 2 + 1;    compiles
default DefaultDepth;  compiles          { pscanner.pp:893's own spelling }
```

The first row carries the weight. If the catch-all were still eating the
operand, an unknown NAME there would take the loop's `tkIdent` field-declaration
branch and say `expected ':'`. A wrong-but-loud message is exactly what a silent
skip cannot produce.

`default 16 77 88 99;` still compiles, and still should: `ConstEval` takes the
16, `Eat(tkSemicolon)` declines the 77, and 77/88/99 fall into the catch-all —
which is frankD's
[[bug-p-a-class-or-record-body-silently-swallows-any-token-it-does-not-recognise]],
deliberately landed AFTER this one so the narrowing counts against a tree where
`default` no longer feeds it.

## The half that is not in the title, and is the reason this is one commit

**Correcting the flag turns a loud wrong ERROR into a silent wrong VALUE**, for
a spelling this ticket itself names.

A class whose only `default` is a value clause used to set `propIsDefault`, so
`t[0]` was REFUSED — with the wrong words (`default property is write-only`
against fpc's `No default property available`), but refused. With the flag
correct, that same source stops looking like it has a default indexed property
and reaches the fall-through instead: a raw `AN_INDEX` over the INSTANCE
POINTER. It printed **375390216**, then **-1189085176** on the next run of the
same program. Silent, not a crash.

The hole is PRE-EXISTING, not introduced — a class with no `default` clause at
all already answered garbage there (148897800 on pin v404, -1189085176 at tip) —
which is why the answer is a refusal in the parser rather than a revert of the
split. But shipping the split alone would have traded a loud error for a wrong
number, and that is strictly worse than the bug being fixed.

**TWO LOOPS, AND ONLY ONE OF THEM WAS OBVIOUS.** `t[0]` goes through
`ParseLValueAST`'s suffix loop; `TC(t)[0]` goes through the CHAINED walker,
which never asked the question at all and answered 130481955799048 with the
first loop already fixed. The refusal is in both. Sibling-arm discipline from
`normalise-dont-special-case.md`, and the cast spelling is the arm that stays
broken if you only run the first repro.

### The row that caught the first version of the refusal

**`not IsNodeArray(node)` is half the condition, not a defensive extra.**

The first version refused on `(tk = tyClass) and (recName >= REC_UCLASS_BASE)
and (FindDefaultProp < 0)` alone. It was green on all three repros AND on
`gate.sh quick`, and it broke `lib/rtl/classes.pas:844`:

```pascal
FComponents: array of TComponent;
...
c := FComponents[FComponentCount - 1];
```

`tk`/`recName` describe an array's **ELEMENT**, so an ordinary dynamic-array
subscript arrives at that arm wearing `tk = tyClass` and the TComponent
`recName`, indistinguishable from an instance subscript — and the fall-through
being called a hole is exactly where it BELONGS. Nothing was stale and nothing
was lying: `tk` was correct about the element of a container and was read as
correct about the container. The generalisable form: **when a guard's condition
is built from a node's TYPE fields, ask what else those fields describe.**

The quick tier could not have caught it — `compiler.pas` contains no
`array of <class>` subscript — and the full Pascal suite is what said so.

## Tests

`test/test_a_property_default_clause_is_two_clauses.pas` — 13 rows against
`fpc -Mdelphi` 3.2.2's own output, byte for byte. **DECLARATION ORDER IS THE
WHOLE TEST**: `Depth` (the value clause) is declared ABOVE `Items` (the genuine
indexed `default;`) on purpose. Swap them and both compilers print 100, so a
test written in the natural order is green against the broken compiler. Rows
D..H are the value forms that were refused outright — named constant, constant
expression, `nodefault`, `stored False`, `stored <method>`, and `stored` and
`default` on one property.

`test/test_a_class_with_no_default_property_cannot_be_subscripted.pas` — the
negative half, **one row per compile, selected by `-dROW_A/B/C`, and that is not
tidiness**. The check is an `Error()` and `Error()` halts, so all three rows in
one file report only the first: a `grep -c` of 1 that passes whether the other
two are refused or silently print garbage, with two thirds of the assertions
unable to fail. Three compiles, three greps, and a fourth compile with NO row
selected which must SUCCEED — otherwise the three greps could be measuring an
unrelated error in a file that never reached the check. The class name differs
between rows (TC vs TPlain) so a message traces to the row that produced it.

**Gate:** `tools/gate.sh quick` with the tree DIRTY (FPC seed canary PASS; 16
rows PASS; the only RED is `pinned builds live lib/rtl`, frankZ's `8374118ec`
waiting on an owner-only pin). AND `PXX_ALLOW_FULL_SUITE=1 make test`, which was
not optional here and is why: quick was green on a change that broke
`lib/rtl/classes.pas`.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
