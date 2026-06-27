# Pointer dereference collapses past depth 2 (Pascal `P^^^` / C `***p`)

- **Type:** bug (shared type model — Track A)
- **Status:** backlog
- **Owner:** unassigned
- **Found / Opened:** 2026-06-27 (Track A+C, while reviewing the lua C-frontend
  pointer-type fixes — measured, not assumed)

## Symptom

Three-level (and deeper) pointer dereference is broken in **both** frontends.
Depth 1 and depth 2 work; depth 3 fails.

Pascal:

```pascal
type PInt=^Integer; PPInt=^PInt; PPPInt=^PPInt;
var x:Integer; p1:PInt; p2:PPInt; p3:PPPInt;
begin x:=42; p1:=@x; p2:=@p1; p3:=@p2;
  WriteLn(p1^);    { 42  ok }
  WriteLn(p2^^);   { 42  ok }
  WriteLn(p3^^^);  { error: "dereferenced value is not a pointer" }
end.
```

C (same shape, segfaults instead of erroring):

```c
int x=42; int *p1=&x; int **p2=&p1; int ***p3=&p2;
*p1;   /* 42 ok */
**p2;  /* 42 ok */
***p3; /* SEGFAULT */
```

| depth | Pascal | C |
|-------|--------|---|
| 1 `p^` / `*p`   | ✅ | ✅ |
| 2 `p^^` / `**p` | ✅ | ✅ |
| 3 `p^^^` / `***p` | ❌ compile error | ❌ segfault |

## Root cause (mechanically traced)

The deref postfix handler reads **one** level of element type from the
*symbol*, and never records the remaining pointer-element chain on the
`AN_DEREF` node it produces. So the next deref has nothing to read and falls to
the default.

`compiler/parser.inc` ~1290 (`tkCaret` / `^` postfix): when `tk = tyPointer`,
it inspects the *operand node kind* and pulls `PtrElemTk`/`PtrElemRec`:
- `AN_IDENT` → `Syms[i].PtrElemTk/PtrElemRec`
- `AN_FIELD` → `UFldPtrElemTk/Rec`
- `AN_INDEX` → base sym `PtrElemTk/Rec`
- **else → `tk := tyInteger; recName := REC_NONE`**  ← the collapse

There is **no `AN_DEREF` case**. Walking `p3^^^`:
1. `^` on `p3` (AN_IDENT): `tk := PtrElemTk(p3) = tyPointer` (PPInt is a
   pointer). Node is now `AN_DEREF`.
2. `^` on the `AN_DEREF`: `tk` is still `tyPointer`, but the operand is
   `AN_DEREF` → no case → **else → `tk := tyInteger`**. (Happens to be the
   correct final type for a 2-level int pointer, which is why depth-2 "works" —
   by luck of the default.)
3. `^` on the next `AN_DEREF`: `tk` is now `tyInteger`, so the outer
   `if tk = tyPointer` is false → `Error('dereferenced value is not a pointer')`.

The C frontend has the *same* shape: `CNodeIsPointer` / `CNodePointeeTk` /
`CNodePtrElemRec` (`compiler/cparser.inc`) are per-AST-node-kind switches that
read one level. The 2026-06-27 fix added an `AN_DEREF` case to
`CNodeIsPointer`/`CNodePtrElemRec` (commit b00ecae5) so `(*p)->field` works —
but that only carried **one** extra level (depth 2). It did not make the
resolution recurse, so C also dies at depth 3 (and there it segfaults rather
than erroring, because the missing element record lets a wrong-typed load
through).

## Why it matters / why it slipped

- The pointer *machinery* (IR load/store, codegen) is fine; this is purely
  **type propagation** through the deref chain.
- Pascal's nominal named types carry depth-1 (and accidentally depth-2)
  uniformly, so it looked solved. Real Pascal rarely uses `^^^`.
- C uses pointers structurally everywhere, so it exposes the cracks first, but
  the limit is in **shared** type-model code, not a C-only bug.
- lua only needs depth ≤2 (`StackValue*`, `Node**`, `char**`), which is why the
  pxx-compiled lua works end to end despite this.

## Fix direction (the real one: recurse)

Stop reading element type from the operand *symbol* one level at a time. Instead
**record the dereference result's pointer-element info on the `AN_DEREF` node
itself** (an `ASTPtrElemTk`/`ASTPtrElemRec`, or reuse `ASTTk` + a side field),
and have the deref handler (and the C `CNode*` helpers) read from the node when
the operand is itself an `AN_DEREF`/`AN_INDEX`/cast — i.e. resolve the pointee
of an arbitrary pointer-valued expression by recursion, not by a per-kind table
that only knows symbols/fields. One fix point lifts both Pascal `^` (parser.inc)
and C `*`/`->` (cparser.inc `CNode*`), since both feed the same AST/IR.

Shared internals (AST node fields, parser, cparser, defs) → Track A. Gate:
`make test` + self-host byte-identical + the depth-3/4/5 cases above (add a
Pascal `test/` and a C `test/c…_b*.c` fixture, both returning 42 through a
deep write+read).

## Repro fixtures (kept)
`/tmp/ptri.pas` (Pascal depth-3), `/tmp/cdeep.c` (C depth-5 + struct via `**`).

## Audit

- 2026-06-27 — C half fixed as a side effect of
  `bug-c-chained-pointer-index-loses-base-type`: `test/cnested_pointer_b94.c`
  now covers scalar `***p` and struct fields through `**`. The shared ticket
  stays open because the Pascal `P^^^` repro still fails at compile time with
  `dereferenced value is not a pointer`.
