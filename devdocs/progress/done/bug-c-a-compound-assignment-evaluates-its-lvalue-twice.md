---
track: C
prio: 60
type: bug
blocked-by: []
summary: "`x OP= y` desugars to `x = x OP y` REUSING the lvalue AST node, so a side-effecting lvalue runs twice: `*f() += 1` calls f twice and `*p++ += 1` advances p by TWO. Idiomatic C, silently wrong, values still plausible."
status: done
owner: frank1-ACP
---

# A compound assignment evaluates its lvalue TWICE

- **Track C** (C frontend: the `OP=` desugar in `cparser.inc`).
- Found 2026-08-20 while fixing
  [[bug-c-a-dereferenced-call-on-the-left-of-an-assignment-runs-twice]], which
  fixed the PLAIN `=` destination. This is a **different mechanism** and
  survives that fix: there the one lowered node had two consumers, here the
  frontend hands the lowering **two independent copies of the lvalue**, so no
  amount of IR-level sharing can help.

## Measured (gcc says 1 everywhere)

| shape | gcc | pxx |
| --- | --- | --- |
| `*lbump() += 1` | 1 call | **2** |
| `lbuf[ibump()] += 1` | 1 call | **2** |
| `sbump()->a += 1` | 1 call | **2** |
| `lbump()[0] += 1` | 1 call | **2** |
| `*p++ += 1` | p steps 1 | **p steps 2** |
| `++*lbump()` / `(*lbump())++` / `--*lbump()` | 1 call | 1 — already correct |

The increment operators are the model: `AN_INCDEC` lowers the address once.
Only the compound-assignment desugar is wrong.

## Mechanism

`ParseCAssignExpr` (`compiler/cparser.inc`, the `tkPlusEq..tkShrEq` arm):

```pascal
{ x OP= y  ==>  x = x OP y. The left operand node is reused as the
  binop's left; since it is a pure lvalue read this is safe. }
rhs := CMakeBinop(baseOp, left, rhs);
node := AllocNode(AN_ASSIGN);
ASTLeft[node] := left;
```

`left` is the SAME AST node index in both places. `IRLowerAST` walks it twice —
once as the binop's value operand, once as the assignment destination — and
each walk emits the side effect. The comment states the invariant the code then
breaks: an lvalue is **not** always a pure read in C.

## Why not just use AN_COMPOUND_ASSIGN

There is already an `AN_COMPOUND_ASSIGN = 70` node whose docstring says "C
assignment expression yielding a value... the lvalue address is computed ONCE",
produced today only by the SHARED expression tail in `parser.inc` (so: NilPy,
and Pascal never). Adopting it in cparser looks like a one-line fix and is a
trap: its lowering is a raw scalar read-modify-write —
`IR_BINOP(load_mem(addr), rhs, op)` typed by the lvalue's own kind — with no
pointer-arithmetic SCALING, so `p += 1` on a `long long *` would step one byte.
NilPy hit the same rawness from the other side and had to route variants back
out of the node
(bug-nilpy-augmented-assign-to-a-variant-typed-field-corrupts-it). Fixing the
node to type like the AST binop is a bigger job than the one below and would
put C on a path Pascal does not use.

## Recommended fix — hoist the lvalue's side-effecting OPERANDS, not the lvalue

Keep the existing typed desugar (it inherits all of C's conversion, promotion
and pointer-scaling rules from the ordinary binop path) and make its shared node
**pure** first, in cparser, before the rewrite:

```
*f()      += 1   ==>  (ptmp = f(),  *ptmp      += 1)
a[i++]    += 1   ==>  (itmp = i++,  a[itmp]    += 1)
f()->m    += 1   ==>  (ptmp = f(),  ptmp->m    += 1)
*p++      += 1   ==>  (ptmp = p++,  *ptmp      += 1)
```

Hoisting the OPERANDS rather than the lvalue's address is what keeps the typing
trivial: each temp takes the type of the expression it replaces (the call's
return type, the index's integer type), and the lvalue's SHAPE — and therefore
its type, its element stride, its record id — is unchanged. Hoisting `&lvalue`
instead would need the temp's pointer-element metadata rebuilt to match, which
is where the scaling bugs live. `CScalarLitLValue` in the same file is the
existing pattern for synthesising a temp plus a comma/sequence at AST level.

Only hoist when the operand is impure (contains a call, an increment, or an
assignment); an ordinary `a[i] += 1` must keep its exact current IR.

## Why it matters

`a[i++] += x` and `*p++ += 1` are ordinary C, not corner cases, and the failure
is a doubled side effect with a **correct stored value** — invisible to any
output comparison, which is how the plain-`=` half of the family survived the
whole corpus (lua, sqlite, tcc, zlib, quickjs) until a csmith checksum found it.

## Gate

The shapes above match gcc; a test under `test/` pins each of them (the
`cassign_dest_call_once.c` sibling is the model); C tests green + self-host
byte-identical.


## What it was — and why the fix is in the IR, not in cparser

The diagnosis in the ticket held: `ParseCAssignExpr` reuses the one lvalue AST
node, so `IRLowerAST` walks it twice and runs its side effects twice. What
changed is where the repair landed.

Rewriting the desugar in cparser — hoisting the lvalue's side-effecting operands
into temps and re-emitting `(tmp = f(), *tmp += 1)` — would have had to rebuild
each temp's type metadata (pointer element kind, depth, record id) to keep the
binop typing and pointer SCALING identical, which is exactly where this family's
bugs live. So the AST is left alone and only the shared node's LOWERING is
pinned:

- `IRLowerCompoundAssign` lowers the destination address once
  (`IRLowerDestAddress`, which parks a call-bearing address in a pointer temp),
  reads through it once, and holds `IRCompoundLvAST/Addr/Val` for the duration of
  the RHS.
- `IRLowerAST` and `IRLowerDestAddress` answer from that pin when they are asked
  for the same AST node again — so the second walk yields the already-read value
  instead of re-running the call. Saved and restored around the recursion, so a
  nested compound assignment keeps its own pin.
- `IRAssignIsSharedCompound` is the trigger, and it is deliberately narrow: C
  mode, an AN_BINOP RHS, the destination node reachable inside it, a scalar /
  float / pointer destination, and an lvalue that actually HAS a side effect.
  Ordinary `a[i] += 1` keeps the exact IR it had.

Because the AST is untouched, the binop keeps deriving its conversions and its
pointer scaling from the real lvalue node — `*pp += 3` on a `long long **`
still steps 24 bytes, which is the property that switching to
`AN_COMPOUND_ASSIGN` would have lost.

## Two things measurement caught that reasoning would not have

**A plain-char lvalue outlived the first cut.** The exact-identity check
(`ASTLeft[binop] = ASTLeft[assign]`) missed it: a `char` lvalue arrives
PROMOTED, as `((lv & $FF) ^ $80) - $80`, so the shared node sits three binops
down the left spine. The trigger now searches the RHS subtree for the node index
instead of guessing a depth — node identity is the signature, and only the
desugar produces it.

**A float lvalue segfaulted.** `dbuf[f()-1] += 0.25` crashed on a null pointer.
The parked address was an `IR_INDEX` node, and an address node carries the
element type it points AT — so with a `double` element the store into the
pointer temp hit the emitter's C double→int rule and truncated an ADDRESS
through `cvttsd2si`. It is the same trap the `IR_LEA` exclusion in
`EmitStoreVar` documents (that one crashed sqlite3AtoF); the node is retagged as
the pointer it is in that position. gdb on the faulting instruction found it in
one step; nothing about the IR dump looked wrong.

All shapes in the ticket's table now match gcc, plus the value form, the nested
form, the shift/bitwise forms and pointer scaling, pinned in
`test/cassign_compound_lvalue_once.c`. quickjs's smoke stays byte-exact.

## Log
- 2026-08-20 — resolved, commit ed49b3ef7.
