---
track: A
prio: 60
type: bug
blocked-by: []
summary: "`y = (x = f())` with a struct-typed f called f() TWICE. Every VALUE came out right — only the side effects doubled — so the whole real-world C corpus missed it and a csmith checksum found it. The count grew with the chain: 1 + one call per chained assignment."
status: done
---

# A struct assignment used as a value runs its RHS twice

Found by the csmith differential campaign
([[feature-c-csmith-differential-fuzzing]]), seed 90202, 2026-08-15. Filed and
fixed in the same sitting; kept as its own ticket because the mechanism is
worth writing down.

## Repro

```c
struct S { int a; int b; };
static int calls = 0;
static struct S f(void) { calls++; struct S s; s.a = 1; s.b = 2; return s; }

int main(void) {
  struct S x, y, z;
  calls = 0; y = (x = f());      /* gcc: 1    pxx: 2 */
  calls = 0; z = y = (x = f());  /* gcc: 1    pxx: 3 */
}
```

`j = (i = g())` with an `int` was always right — the scalar arms already had
the rule.

## Mechanism

`IRLowerAST`'s AN_ASSIGN arm ends the scalar paths with an explicit re-read:

```pascal
Result := IRAppend(IR_STORE_SYM, ...);
{ In C an assignment is an expression yielding the stored value, so load it
  back; this lets `g(p = x)` / `(p = x)->f` use the value. }
if CProgramMode then
  Result := IRAppend(IR_LOAD_SYM, ...);
```

The RECORD arms never got the aggregate half of that rule and returned the
`IR_COPY_REC` node itself. So `y = (x = f())` lowered to

```
4: call
5: copy_rec  dest=x  src=4
6: copy_rec  dest=y  src=5     <- the inner COPY_REC as an operand
```

and node 5 is BOTH a statement in the flat IR list AND an operand of node 6.
The emitter walks it at top level, and then walks it again as node 6's source
— re-emitting its whole subtree, call included.

The values were still right (the second call recomputes the same struct), which
is exactly why lua, sqlite, tcc, zlib and c-testsuite all missed it: a
side-effect-free RHS is indistinguishable. csmith's oracle is a checksum over
globals, and the doubled call mutated one.

## Fix

One place, mirroring the scalar comment: at the end of the AN_ASSIGN arm, in
C mode only, when the result is an `IR_COPY_REC`/`IR_COPY_REC_MANAGED`, the
node's value becomes `IRLowerAddress(ASTLeft[node])` — a record's "value" in
this IR is carried by address, so the re-read of the destination IS its
address. Pascal keeps the store node as its result, so the self-host build
stays byte-identical.

Fixing it per-arm was the alternative and was rejected: there are seven
`IR_COPY_REC` result sites in that arm (whole record, managed record, static
array, dyn-array row, array-from-call, ...) and the one that gets missed is the
one that stays broken.

## Verified

- The 1182-line seed-90202 generator now agrees with the gcc oracle exactly.
- `test/cstruct_assign_value_side_effects.c` — five shapes (plain LHS, deref
  LHS, statement form, three-deep chain, initialiser) each asserting BOTH the
  call count and the copied values, checked against gcc on the same source.
  Wired in beside `cassign_value_b43.c`, whose scalar half it completes.
- `tools/gate.sh quick` GREEN, self-host fixedpoint byte-identical.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
