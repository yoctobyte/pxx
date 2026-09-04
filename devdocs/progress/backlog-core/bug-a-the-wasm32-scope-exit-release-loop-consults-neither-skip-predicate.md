---
track: A
prio: 30
type: bug
blocked-by: []
status: backlog
summary: "wasm32's WasmEmitManagedLocals is the SEVENTH copy of the scope-exit release loop and consults neither StacklessPersistentSlotSym nor SymSkipScopeExitRelease -- so the `except V as e` binder skip that fixes a use-after-free on the other six is absent there. Still not reachable, but the reason CHANGED on 2026-09-04: the PAL wall is gone and a .npy program now COMPILES for wasm32, so what blocks it is that such a module is not yet RUNNABLE (IR_ZERO_SYM and a rejected encoding). The stackless half was TESTED and is FINE -- a Pascal stackless generator holding an AnsiString across a yield prints sum=15 on wasm32, matching x86-64 -- so this is one gap and not two."
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

**It is now blocked one step later: such a module is not RUNNABLE.** Four
bodies still refuse on `statement IR op 51` (IR_ZERO_SYM), `op 60` and `op 32`
appear too, and wasmtime rejects the module outright with `invalid var_u32:
integer representation too long`. Those are wasm32 codegen and sit under
[[umbrella-wasm-is-a-real-platform]].

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
