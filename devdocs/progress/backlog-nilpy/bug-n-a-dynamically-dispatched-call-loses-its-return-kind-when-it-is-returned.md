---
slug: bug-n-a-dynamically-dispatched-call-loses-its-return-kind-when-it-is-returned
title: a dynamically dispatched call loses its return kind when it is returned
summary: >
  `def via(o): return o.lst(1)` on an unannotated receiver answers a RAW POINTER
  printed as an integer where CPython prints the list. The dyn-dispatch node is
  typed tyVariant by the frontend and pydyn_meth1 returns a Variant, so the loss
  is in the enclosing def's inferred RETURN type: `print(o.lst(1))` inline and
  `x = o.lst(1)` are both correct in the same program, and only `return` is
  wrong. Broken for list, dict and str results at arity >= 1; an arity-ZERO dyn
  call (`return o.lst0()`) is correct, which is the discriminator. Silent wrong
  value.
track: N
type: bug
prio: 65
owner: unassigned
status: open
---

## Measured 2026-09-13 (frankH), at 622de7c9494f

One program, four spellings of the same call. The receiver is an unannotated
parameter, so the call is dispatched at run time (pydyn_meth1):

    class P:
        def lst(self, a):
            return [a, a + 1]

    def direct(o):    print("inline ", o.lst(1))       # [1, 2]   correct
    def viaLocal(o):  x = o.lst(1); print("local  ", x) # [1, 2]   correct
    def viaRet(o):    return o.lst(1)                   # 134445644382280  WRONG
    def viaLen(o):    return len(o.lst(1))              # 2        correct

    p = P()
    print("return ", viaRet(p))

Per result kind through the `return` spelling: a list, a dict and a STR are all
wrong; an int is right. Per ARITY: `def lst0(self): return [7, 8]` returned
through the same shape is CORRECT, so the discriminator is the arity of the
dispatched call and not the kind alone.

`p.lst(1)` spelled directly on a typed receiver is correct throughout, so no
probe of "does lst work" can see this.

## Where it is NOT

- The frontend types the call node `tyVariant` and sets `LastExprTk :=
  tyVariant` (pyparser.inc, the tail of the dyn-dispatch builder), and every
  `pydyn_meth<n>` / `pydyn_methkw<n>` / `pydyn_methl` in pyeval.pas is declared
  `: Variant`. So the node and the callee agree.
- `PyDynMethN` differs between arity 0 and arity >= 1 only in how many
  `args.append` calls run, which is the wrong shape to explain a lost RESULT
  kind — worth confirming rather than believing.

So the suspect is the enclosing def's own inferred return type: an int/pointer
return convention chosen for a body whose single `return` is a Variant
expression. `PXXDBG=n.locals` on the enclosing def is the first instrument.

## How it was found

By a fixture for a DIFFERENT question. `test_nilpy_open_world_arity_is_not_truncated.npy`
wanted `[a+b+c+d+e, f, len(rest)]` from a run-time dispatched method to prove
that written arguments past four are neither dropped nor defaulted over, and the
list came back as a pointer. The row now encodes the three facts in one INTEGER
and says why, so the two bugs are not entangled — but a fixture asserting a
container result through that path is the natural spelling and would have been
red for a reason that has nothing to do with arity.
