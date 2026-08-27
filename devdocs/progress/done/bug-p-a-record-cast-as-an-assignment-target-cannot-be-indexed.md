---
track: P
prio: 45
type: bug
summary: "`TRec(x).field[i] := v` is a parse error — the statement-level cast-as-lvalue arm hand-rolls its own postfix walker, and that walker knows `^` and `.field` but not `[`. The same expression as an r-value parses fine, and so does the same target one field shallower."
status: done
---

# A record typecast used as an assignment target cannot be indexed

- **Type:** bug (Pascal frontend) — **Track P**, tag compat
- **Found:** 2026-08-27, marching the real FPC compiler sources
  (`/data/borg-rescue/home-rene/src/fpc-source/compiler`). `cutils.pas:331` is
  `reverse_longword`, and it is the second unit in, so everything behind it is
  unreachable.

## Measured

```pascal
type TRec = packed record b: array[0..3] of Byte; n: Byte;
                          inner: record q: Byte; end; end;
var l, r: LongWord; x: TRec;
```

| statement | result |
| --- | --- |
| `writeln(TRec(l).b[0]);` | ok |
| `writeln(TRec(l).n);` | ok |
| `TRec(r).n := 5;` | ok |
| `TRec(r).inner.q := 5;` | ok |
| `x.b[0] := 5;` | ok |
| **`TRec(r).b[0] := 5;`** | **`Expected: :=, but got: [`** |

So it is not casts, not record fields, not indexing, and not lvalues — it is
exactly the intersection: an index applied to a field of a **cast used as an
assignment target**.

FPC's own use, `cutils.pas:330`:

```pascal
TLongWordRec(reverse_longword).b[0] := reverse_byte(TLongWordRec(l).b[3]);
```

The right-hand side of that very line parses. The left-hand side does not.

## Root cause, and why it is not a one-line fix

`compiler/pasparser_stmt.inc:6365` (the record-name-typecast lvalue arm) builds
the cast node and then walks the postfix chain with its own loop:

```pascal
while CurTok.Kind in [tkCaret, tkDot] do
```

`tkLBrack` is not in that set, so the loop stops and the arm demands `:=`.

**Adding a `tkLBrack` arm there is the wrong fix.** The corresponding loop in
`ParseLValueAST` is ~120 lines: N-D fixed arrays folded from both `m[i,j]` and
`m[i][j]` spellings, the partial-row subscript, the dynamic/jagged comma sugar,
`alreadyResolved`, string-value indexing, default properties. Copying any part
of that here makes a **fifth** hand-rolled walker — `ParseLValueAST`'s,
`ApplyCallResultPtrSuffix`, pyparser's twin, this one — and the project already
paid for that once: `bug-pascal-record-cast-chain-drops-method-call` was
`PRec(q)^.cr.Get(3)` silently evaluating to a class reference because the cast
chains had *no* member resolver, and its fix was `ParseMetaclassMemberTail`,
one resolver rather than a fourth partial copy.

So this is the same ticket one level up: the **suffix chain** wants to be one
function, not the **member tail**.

## Fix shape

Extract `ParseLValueAST`'s suffix loop into something that takes a starting
NODE (plus its type kind and record id) instead of a starting SYMBOL — which is
the only reason the cast arm cannot call it today: `ParseLValueAST(idx,
identTokIdx)` is keyed on a resolved symbol, and a cast's base is a node.

Then the cast-as-lvalue arm becomes: build the cast node, call the shared
walker, `Expect(:=)`, `ParseExpr`. `ApplyCallResultPtrSuffix` is the second
caller that should collapse into it, and pyparser's twin is a third to look at.

Do NOT close this by adding `tkLBrack` to the loop.
`devdocs/dev/normalise-dont-special-case.md`;
`devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md`.

## Gate

The six rows above all compile and answer FPC's values; `reverse_longword` from
`cutils.pas` runs; the FPC-compiler corpus march gets past `cutils.pas:331`;
self-host fixedpoint byte-identical.

## Outcome (2026-08-27)

Fixed, and the ticket's own table was wrong about half of it.

**The lvalue half**, as filed. The cast-as-lvalue statement arm
(`pasparser_stmt.inc`) keeps its `^` handling — a cast's pointee rec is carried
on the deref node, which is that arm's own business — and hands `.field`, `[i]`
and everything after them to `ParseClassRecordSelectors`, the node-keyed
selector walker the expression side and the call-result path already share. No
fifth walker, and `tkLBrack` was never added to the hand-rolled loop.

**The rvalue half, which the ticket recorded as "ok".** It is not:

| | FPC | pxx (before) |
| --- | --- | --- |
| `writeln(TLongWordRec(l).b[0])` | `4` | `18486690310128388` |
| `writeln(v.b[0])` (variable) | `4` | `4` |
| `writeln(p^.b[0])` (pointer) | `4` | `4` |

It parsed and answered a wrong value — worse than the parse error that led
here, and it survived because index 3 of a 4-byte record is right by luck
(one byte left) and because the two spellings that always worked go through the
shared walker. Cause: the expression-side cast walker sent only NON-fields to
`ParseClassRecordSelectors` and kept plain fields on a hand-rolled AN_FIELD
builder — after which this loop's own `[` arm hard-codes `tk := tyRecord` and
`ASTTk := Ord(tyRecord)` on the indexed value, so a Byte element was read at the
record's width. The guard is gone: every `.name` on a record-cast chain now goes
to the shared walker.

So the ticket's real shape was not "the lvalue arm is missing a case" but "two
of the four postfix walkers disagree about the same construct, and the one that
parses is the one that lies".

**Not done:** extracting `ParseLValueAST`'s own suffix loop, which the ticket
proposed. Measured first: that loop is **1700 lines** (pasparser_lval.inc
1131-2832) and 33 of the routine's 74 locals appear on both sides of it, so
splitting it is a large, delicate move that wants the full tier rather than the
quick gate. It was not needed here — `ParseClassRecordSelectors` is already the
shared node-keyed walker the ticket asks for, and both offending arms now call
it. Worth revisiting on its own terms; it is no longer blocking anything.

## Gate

Six rows plus the rvalue table above all match FPC. `reverse_longword` from
`cutils.pas` compiles verbatim — including the cast of the RESULT VARIABLE as
the assignment target — and answers FPC's values.
`test/test_record_cast_indexed_field.pas`.

The FPC-compiler corpus march moves `cutils.pas` from **331 to 463**, where it
now stops on `sqrt` — the elementary math functions are pulled ambiently for a
PROGRAM but not for a UNIT, which is the same shape as the thread and
InterLocked warts and belongs in its own ticket.

Gate: quick GREEN, self-host fixedpoint byte-identical.

## Log
- 2026-08-27 — resolved, commit acd14fe64.
