---
track: A
prio: 55
type: bug
summary: "A NilPy function that returns a container element (`return store[k]`) hands the caller a BORROW the ARC model treats as owned: the caller's local releases it at scope exit and the container's own reference dies. Root cause measured — the dict/list index lowers to an AN_CALL, and IRNodeYieldsOwnedRef reads any AN_CALL as +1, so the return-retain is skipped."
status: done
owner: claude-A-uforth
---

# A borrowed object returned out of a function is over-released

Seven-line repro, wrong answer (not a crash), CPython is the oracle:

```python
store = {}
def ensure(k: int) -> list:
    if k not in store:
        store[k] = [1, 2, 3]
    return store[k]
def m():
    t = ensure(1)
    t[1] = 5
m()
print(len(store[1]), store[1])     # CPython: 3 [1, 5, 3]      pxx: 0 []
```

Everything is correct until `m` RETURNS. Printing inside `m` shows the right
length before and after the mutation; the container's element dies when the
local `t` goes out of scope. `bytearray` behaves the same, as does a list held
in a list rather than a dict. Two shapes are NOT affected: the same code at
module scope (no frame to exit), and an `ensure` with NO return annotation —
unannotated makes `t` a variant (tk=22) rather than a class reference (tk=6),
which takes a different path entirely.

## Root cause

`compiler/ir.inc`'s ARC model (feature-nilpy-object-reclamation slices 4/5) has
one predicate for ownership, `IRNodeYieldsOwnedRef`:

```pascal
IRNodeYieldsOwnedRef := (n >= 0) and
  ((ASTKind[n] = AN_CALL) or (ASTKind[n] = AN_VIRTUAL_CALL) or ...);
```

"A construction is rc=1 out of PXXObjAlloc and a call result carries the
callee's return-retain." Both arms of the model agree: the RETURN arm retains a
borrowed value on the way out, and the ASSIGN arm therefore does not retain a
call result.

The hole is that **a Python index is an AN_CALL**. `store[k]` lowers to a call
into the pylib dict accessor, so the return arm asks
`IRNodeYieldsOwnedRef(store[k])`, gets True, and skips the retain — but a pylib
accessor hands back a BORROW, not a +1. The caller then assumes owned, releases
at scope exit, and the container's reference is what dies.

Measured with `PXXDBG=a.ast:ensure` / `a.ir:ensure`: the `return` node's left
child is kind=8 (AN_CALL) into the dict getter, and the emitted IR for the
return path is `call <getter> -> store_sym tmp -> store_sym $pyresult` with no
`PXXObjRetain` anywhere.

## Why this is not a one-line fix

The predicate cannot answer the question from the AST node alone: `bytearray(8)`
is also an AN_CALL and IS owned. What is missing is per-callee ownership —
"does this proc return a +1 reference?" — which is true for NilPy user functions
(they emit the return-retain) and for pylib constructors, and false for every
pylib accessor. `TProc` has no unit/ownership field and must not grow one
(see the TSymbol-field landmine); a parallel array is the shape.

Belongs with [[feature-nilpy-object-reclamation]] — same model, same file, and
the classification is the piece that ticket has not reached yet. Track A rather
than N: the change is in the shared `ir.inc`, not in the NilPy frontend files.

## Found by

uforth's ANS `blocktest.fth`, via
[[bug-nilpy-uforth-ans-word-set-suite-4-of-13-open]]. `flush_blocks` does
`self._ensure_block(blk)[:] = self.memory[addr:addr + BLOCK_SIZE]` against an
`_ensure_block(self, blk) -> bytearray` — so the block store's buffer is freed
the moment the flush helper returns, and the next block access segfaults. The
word set dies at `1 BLOCK DROP UPDATE` + `FLUSH`, five TESTING groups in.

## Gate

The repro above matches CPython, `make test-nilpy` green, self-host
byte-identical, and blocktest.fth byte-identical to CPython running the same
uforth.py.

## Log
- 2026-08-08 — resolved, commit e062155c5.
