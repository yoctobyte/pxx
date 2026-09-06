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

## 2026-09-06, later — the regression does NOT reproduce at HEAD, and the control everyone is being handed is INERT (frank-coord-core)

frankwasm's negative result has been circulating with a positive control
attached: *"whatever you change, `yield 1; yield 2` must still print both."*
**That control cannot fail for this patch.** Measured below.

### What was run

The patch, in the shape frankwasm recorded (`0819a7f5f`) and the one the six
correct arms use — the predicate applied PER SYMBOL on the loop, not as a
blanket exit:

```pascal
  for i := Procs[CurProc].ScopeBase to SymCount - 1 do
    if (not SymSkipScopeExitRelease(i)) and
       (Syms[i].Kind = skLocal) and not Syms[i].IsRef and (i <> retSym) then
```

Built to fixedpoint (`20d814eef8e7`), against baseline `0426b285ba35`. Four
generator shapes, each compiled for x86-64 as the oracle and for wasm32 both
with and without the patch:

| shape | what it holds across the yield | module changed by the patch? | wasm32 vs x86-64, patched |
| --- | --- | --- | --- |
| `yield 1; yield 2` | nothing | **byte-identical** | agree (`1 2`) |
| string local | an AnsiString | differs, 36617 bytes | agree (`21 22`) |
| two string locals, one made after the first yield | two AnsiStrings | differs, 35271 bytes | agree (`4 5`) |
| object local | a NilPy class instance | differs, 40086 bytes | agree (`5 6`) |

### The two findings, and the first one is the one to carry

**1. `yield 1; yield 2` IS A GUARD THAT CANNOT FAIL FOR THIS CHANGE.** The
emitted module is byte-identical with and without the patch. It has no managed
local, so no symbol in it can satisfy `StacklessPersistentSlotSym`, so the
predicate never fires and there is nothing for the patch to change. It is a
real control for the compiler in general and an inert one for this patch
specifically — CLAUDE.md's rule that a control must be drawn from the
population the question is about, met exactly. **A control drawn from the wrong
population passes and certifies the broken instrument**, and this one has been
handed to at least three sessions as the thing to check.

Anyone testing this loop needs a generator that HOLDS A MANAGED LOCAL ACROSS A
YIELD. The three rows above do; the circulating one does not.

**2. THE REGRESSION DOES NOT REPRODUCE AT HEAD.** All three shapes that the
patch actually changes agree with the x86-64 oracle. This does NOT say
frankwasm was wrong — they measured what they measured, and I do not know which
two rows failed. The likely explanation is their own: the bug they were chasing
turned out to be `99fa7984f`, a Variant stored through a pointer, and that fix
landed between their measurement and this one. **What is claimed here is
narrow: at this tree, with this patch, these four shapes. Not "the patch is
safe".**

### Still not enough to land it

What is still missing is a case that DISTINGUISHES the two behaviours — a
program that is WRONG without the predicate and right with it. The predicate
exists to stop a double release and a use-after-free, and neither shows up as a
wrong value in a program that never had the bug. Reason (2) of the predicate
cannot even be written in NilPy today: `yield` inside `try`/`except` is refused
outright ("stackless generator: yield only allowed at top level or inside
for/while/if/case"), so the `except C as e` binder and a generator frame cannot
coexist. That leaves reason (1), the stackless persistent slot, as the only
half reachable on this target — and it fires, as the table shows.

So the next step is not "apply it and see", which is now two sessions' worth of
inconclusive greens. It is to construct the failing program the predicate
exists for, on a target where it is absent, and watch it fail.
