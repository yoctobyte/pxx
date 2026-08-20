---
track: A
prio: 35
type: bug
blocked-by: []
summary: "pxx releases a by-value interface argument at the CALLER's scope exit; FPC releases it at CALLEE return. Every object is still destroyed exactly once, so this is a lifetime-timing divergence rather than a leak — but a destructor with side effects (closing a file, dropping a lock) runs later than the program says, and the last object of a batch stays alive until the calling routine returns."
status: backlog
owner: unassigned
---

# A by-value interface param dies at caller scope exit, not callee return

- **Track A** (`compiler/ir.inc`, `IRLowerCallArg`).
- Split out of `bug-a-an-interface-passed-by-value-leaks-a-reference-per-call`
  (the leak half is fixed and tested; this is the residue).

## Measured

```pascal
procedure TakeVal(f: IFoo); begin ... end;
f := live;      { rc 1 }
TakeVal(f);
                { FPC: rc back to 1 after the call — the callee released it }
                { pxx: rc still 2 — the caller's temp holds it }
f := nil;       { FPC: destroyed here.  pxx: still alive }
```

Destructor-print ordering makes it plain:

| | FPC | pxx |
| --- | --- | --- |
| 5 objects, loop in main body | 5×DESTROY then `END OF MAIN` | 4×DESTROY, `END OF MAIN`, then the 5th |

Counts always reconcile — nothing leaks. Only the moment differs.

## Cause

The ownership models differ. FPC gives the **callee** the reference: it is
retained by the caller and released by the callee on return. pxx models the
by-value argument as a **caller-side temp** whose reference is released by
`EmitManagedLocalCleanup` at the caller's scope exit (or, for a main-body call
site, by the program-exit pass).

## Why it was not fixed with the leak

The exact-FPC fix is to release the temp immediately after the call returns.
That is not a local edit: `IRLowerCallArg` returns a value into 15+ call sites
and the release has to be appended *after* the call node, so it needs a pending
list with a nesting marker to stay correct for `f(g(x))`. That is an ownership
change in Track A's hottest lowering function, and the leak — the severe half,
unbounded growth — is already fixed and gated without it.

## Sizing note

Same family as the already-resolved `bug-pascal-mainbody-ascast-temp-finalization-timing`
and the as-cast routine-scope timing: pxx keeps expression temps alive to a
scope boundary where FPC drops them earlier. Worth deciding once for **all** of
them rather than per-construct — if that is the call, this is really a Track U
`decide-*` about managed-temp lifetime, not four separate bugs.

## Gate

Track A: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`.
Extend `test/test_interface_byval_param_no_leak.pas` — it deliberately checks
counts AFTER the owning routine returns, and would tighten to check them inside.
