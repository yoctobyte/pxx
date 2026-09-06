---
track: A
prio: 30
type: bug
blocked-by: []
status: backlog
summary: "wasm32's WasmEmitManagedLocals is the SEVENTH copy of the scope-exit release loop and consults neither StacklessPersistentSlotSym nor SymSkipScopeExitRelease -- so the `except V as e` binder skip that fixes a use-after-free on the other six is absent there. TWO PREMISES OF THIS TICKET ARE NOW STALE and are corrected below: (1) it is REACHABLE -- a .npy program compiles AND RUNS on wasm32 today, measured 2026-09-06 under wasmtime; (2) `this is one gap and not two` was wrong -- the same loop also had NO tyClass arm at all, an unconditional object-local leak, fixed in d58828d8c and guarded by test/wasm/check_nilpy_objlocal.sh. The skip-predicate half remains open and the naive patch for it is KNOWN to regress two generator rows for a reason nobody has explained."
---

# wasm32's release loop consults neither skip predicate

## What was checked, and how

Applying the rule frankA sent on the frozen-string emitter set — **grep for who
does NOT call the predicate, not for who does** — to
`SymSkipScopeExitRelease`, which was just added and wired at six sites:

```
$ grep -n 'ScopeBase to SymCount' compiler/*.inc
```

Six of the hits are the arms of `EmitManagedLocalCleanupForTarget`
(`symtab.inc` + five in `ir_codegen.inc`), all now guarded. Five more are
per-backend ZERO-INIT walkers, which are not release loops. The remaining one is
`WasmEmitManagedLocals` (`ir_codegen_wasm32.inc:6391`), which IS a release loop:

```pascal
  for i := Procs[CurProc].ScopeBase to SymCount - 1 do
    if (Syms[i].Kind = skLocal) and not Syms[i].IsRef and (i <> retSym) then
```

No `StacklessPersistentSlotSym`, no `SymSkipScopeExitRelease`. It is called from
BOTH the ordinary epilogue (`:6797`) and `WasmEmitProcCleanupPad` (`:4266`), so
the pad path has no binder skip.

## Why it is not a crash today — and the reason changed on 2026-09-04

The release arm that matters is gated on `NilPyUserCode` (via
`PyClassSymArcEligible`), so it needs a `.npy` program running on wasm32.

**Originally that was blocked at COMPILE time** — `undefined variable
(SYS_openat)`, which is why this ticket was filed `blocked-by` the PAL ticket.
That is fixed: pypal emits no syscall on a target without a table, wasm32
derives `PLATFORM_WASI`, and a `.npy` program now builds for wasm32.

**It is now blocked one step later: such a module is not RUNNABLE.** Two walls
fell in one evening and this one is behind the second.

The encoder wall is GONE: `invalid var_u32` was a local index of -1 and frankA
fixed it in `f01eee6fa`
([[bug-a-wasm32-emits-a-local-index-of-minus-one-so-every-nilpy-module-fails-validation]]).
A NilPy module for wasm32 now VALIDATES.

What remains is the codegen tail. Re-measured at `fbc02f487f6f`: both tests
that would exercise this ticket still trap on `unreachable`, because bodies are
still refused on `value IR op 32` (IR_RTTI_REG in `GetClass`) and `statement IR
op 60` in the closure helpers. Those are wasm32 codegen, frankA holds them, and
they sit under [[umbrella-wasm-is-a-real-platform]].

The frontmatter edge is REMOVED rather than repointed, because no single open
ticket names that state and a `blocked-by` to a ticket that does not gate it
would be a worse lie than none. When a `.npy` program runs on wasm32, this
becomes live: `raise` or `raise e` from an `except V as e:` handler frees the
object still in flight and the outer handler reads it — the crash the other six
backends had for the length of one commit.

## The stackless half was measured and is FINE — do not fix it

The obvious second worry is the generator persistent-slot guard, also absent
here. It is not a defect:

```pascal
function Gen(n: Integer): Integer; generator; stackless;
var acc: AnsiString; ...   { acc must SURVIVE each yield }
```
prints `sum=15` on wasm32 and `sum=15` on x86-64. Whatever declines first —
`ManagedLocalZeroBytes`, or the slot not presenting as a plain `skLocal` — the
observable is correct. **Measured rather than inferred from the missing call**,
because "the predicate is not called" and "the behaviour is wrong" are different
claims and only the second is a bug.

## When you fix it

`InUnwindCleanupPad` already exists and is set around the shared pad's release.
wasm32's pad would set it around its own `WasmEmitManagedLocals(True, ..)` call
and the loop would ask `SymSkipScopeExitRelease(i)`. Two lines. It was not done
in the commit that added the predicate because it is untestable from here today
and the file has an active owner; a blind edit to an unreachable path in someone
else's working file is the worse trade.


## 2026-09-06 — two premises corrected, and one half of this closed (frank-coord-core)

**REACHABILITY: this ticket said the blocker was that a .npy module "is not yet
RUNNABLE (IR_ZERO_SYM and a rejected encoding)". That is no longer true.**
Measured at `9ae328993`, under wasmtime on this host:

```
$ cat objloc.npy
class Box:
    def __init__(self, v): self.v = v
def hold(n):
    b = Box(n)
    return b.v
print(hold(7))
$ pascal26 --target=wasm32 objloc.npy objloc.wasm && wasmtime run objloc.wasm
7
```

Compiles, validates, runs, prints the right answer. So every claim in this
ticket is now measurable at runtime rather than by reading, and the ranking
should reflect that: an unchecked path on a target nobody can run is a different
thing from an unchecked path on a target that runs.

**"ONE GAP AND NOT TWO" WAS WRONG, AND THE SECOND GAP WAS THE BIGGER ONE.**
This ticket correctly identified the missing skip predicates. It did not notice
that `WasmEmitManagedLocals` was also missing an entire release row: the
`tyClass` arm that all six other copies carry. `PXXObjRelease` appeared nowhere
in `ir_codegen_wasm32.inc`. Every NilPy object bound to a local leaked once per
call on wasm32 and on no other target:

| target | N=2000 | N=8000 | slope |
| --- | --- | --- | --- |
| x86-64 | live=1 | live=1 | flat |
| wasm32 before | live=1900 | live=7815 | ~1 block/call |
| wasm32 after | live=2 | live=2 | flat |

Fixed `d58828d8c`, guarded `223127f86` (`test/wasm/check_nilpy_objlocal.sh`,
positive control run against the reverted arm). **How it hid from this ticket:**
this ticket was written by comparing wasm32 against the register arms on the
question it was already asking — the skip predicates — and a missing arm answers
that question the same way a present-but-unguarded arm does. Asking "does it
consult the predicate" cannot see "there is nothing here to consult it".

**WHAT REMAINS OPEN IS EXACTLY THE ORIGINAL CLAIM,** and it is untouched by the
above: the loop consults neither `SymSkipScopeExitRelease` nor
`StacklessPersistentSlotSym`.

**DO NOT APPLY THE OBVIOUS PATCH.** frankwasm already did, with the CORRECT
predicate at the CORRECT granularity, in the shape the six right arms use
(recorded diff `0819a7f5f`), and it regressed two passing generator rows —
`yield 1; yield 2` started printing only `1`. Two explanations were offered and
both were refuted against the recorded diff: it was not `f891bbe8e`'s
blanket-exit mistake, and it was not the wrong predicate. **The wasm32 copy
depends on the release it currently performs, in a way nobody has named.** Name
that before patching, and see
[[refactor-a-the-scope-exit-managed-local-release-loop-has-seven-copies]] for
why the seven copies are the real subject.

Positive control for anyone who picks this up, verified at `cc18bc028`:
`yield 1; yield 2` prints both on native and on wasm32.
