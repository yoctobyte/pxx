---
track: A
prio: 35
type: bug
blocked-by: []
summary: "pxx releases a by-value interface argument at the CALLER's scope exit; FPC releases it at CALLEE return. Every object is still destroyed exactly once, so this is a lifetime-timing divergence rather than a leak — but a destructor with side effects (closing a file, dropping a lock) runs later than the program says, and the last object of a batch stays alive until the calling routine returns."
status: done
owner: agent-A
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

## Fixed — 2026-08-21

The release now happens at the end of the **statement containing the call**, not
at the caller's scope exit. Every shape measured is byte-identical to FPC 3.2.2's
output.

### Why not "at callee return", which is FPC's exact point

Because it is not reachable from this IR. The IR is a **linear list emitted in
APPEND order**, and a call node is emitted through its *statement root*, which is
appended AFTER it. Anything appended between the two therefore runs BEFORE the
call — a release appended "right after the call node" would have released the
temp before the callee ever saw it.

That is the fact the ticket's sizing note was circling without naming. The
"pending list with a nesting marker" it predicted is real, but the flush point
is the statement boundary, not the call:

- `PostCallIntfSym` / `PostCallIntfCount` — a **stack**, pushed by
  `IRLowerCallArg` when it materialises a by-value COM/ARC interface temp.
- `IRFlushPostCallIntf(base)` — emits `PXXIntfRelease(@tmp, ci)` and then a raw
  `IR_STORE_MEM` of nil through the slot address, for everything above `base`.
- The `AN_SEQ` spine walk captures `pcBase` before each statement item and
  flushes to it afterwards. A **base**, not a blanket flush: an inner sequence (a
  compound statement in a branch) lowers while the enclosing statement's own
  temps are still pending, and those belong to the outer boundary.
- `IRReset` clears the stack per body, so nothing can ever name a symbol from
  another stack frame.

### The nil store is what makes a PARTIAL fix safe

This is the part worth keeping in mind before touching it. A temp that gets
flushed is nil by the time `EmitManagedLocalCleanup` (or the main-body
program-exit pass) reaches it, and `PXXIntfRelease` is nil-safe. So a call site
whose statement never flushes keeps **exactly the old behaviour** rather than
double-releasing, and the existing main-body registration stays as the backstop
instead of becoming a second release. The store is an `IR_STORE_MEM` through the
slot address rather than an `IR_STORE_SYM`, so no ARC store logic can release
the slot a second time.

### Measured, not reasoned

Whole-program diff against FPC 3.2.2 on: the ticket's loop; a call inside a
procedure; a nested call `TakeVal(PassThrough(f))`; two arguments; a branch not
taken; a single-statement `if` / `while` / `for` body; an `else` branch; and the
main body. All identical.

Single-statement branch bodies were the shape expected to still diverge (they
are not an `AN_SEQ`, so nothing flushes inside them) — and they do not, because
the `if` is itself a statement in the enclosing sequence and nothing observable
happens between the callee's return and that boundary.

`test/test_interface_byval_param_no_leak.pas` 16 -> 25 cases, and its header note
is corrected: the counts can now be checked **inside** the routine, which is what
the old model could not satisfy. The main-body case is the strongest of them —
that temp used to live to program exit, so nothing could have destroyed it at
all. Green under FPC and pxx, and under qemu on i386, aarch64, arm32, riscv32.

**One expectation was wrong and FPC said so.** The nested case first asserted
that `f := nil` destroys; it does not, in FPC either — `PassThrough`'s FUNCTION
RESULT is a separate temp both compilers hold to routine scope exit. The test now
records what both do, and says why.

### The sizing note's question answers itself

The ticket asked whether this should be a Track U `decide-*` about managed-temp
lifetime for all of `bug-pascal-mainbody-ascast-temp-finalization-timing` and the
as-cast routine-scope timing. It should not, and the reason is that those were
already resolved **in FPC's favour by keeping the temp LATE** — FPC holds a
main-body as-cast temp to end-of-main, and matching it was the fix. This one
needed the temp EARLY, for the same reason: FPC. There is no policy to choose,
only an oracle to match, per construct. No `decide-*` filed.

## Log
- 2026-08-21 — resolved, commit 4c3f76f35.
