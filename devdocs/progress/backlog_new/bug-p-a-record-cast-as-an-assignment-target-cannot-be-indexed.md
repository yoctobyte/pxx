---
track: P
prio: 45
type: bug
summary: "`TRec(x).field[i] := v` is a parse error — the statement-level cast-as-lvalue arm hand-rolls its own postfix walker, and that walker knows `^` and `.field` but not `[`. The same expression as an r-value parses fine, and so does the same target one field shallower."
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
