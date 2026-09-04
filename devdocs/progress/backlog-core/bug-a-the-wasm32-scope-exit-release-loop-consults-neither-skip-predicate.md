---
track: A
prio: 30
type: bug
blocked-by: [bug-n-the-nilpy-pal-issues-raw-syscalls-so-every-file-body-traps-on-wasm32]
status: backlog
summary: "wasm32's WasmEmitManagedLocals is the SEVENTH copy of the scope-exit release loop and consults neither StacklessPersistentSlotSym nor SymSkipScopeExitRelease -- so the `except V as e` binder skip that fixes a use-after-free on the other six is absent there. Not reachable today: the tyClass release arm requires NilPyUserCode and no .npy program builds for wasm32 at all, which is the blocker named above. It becomes live the moment that closes. The stackless half was TESTED and is FINE (a Pascal stackless generator holding an AnsiString across a yield prints sum=15 on wasm32, matching x86-64), so this is one gap and not two."
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

## Why it is not a crash today

The release arm that matters is gated on `NilPyUserCode` (via
`PyClassSymArcEligible`), and **no `.npy` program compiles for wasm32 at all** —
`undefined variable (SYS_openat)`, the blocker in the frontmatter. So the arm
cannot execute. When that closes, wasm32 acquires the use-after-free the other
six backends had for the length of one commit: `raise` or `raise e` from an
`except V as e:` handler frees the object still in flight, and the outer
handler reads it.

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
