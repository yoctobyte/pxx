---
track: A
prio: 45
type: bug
blocked-by: []
summary: "After riscv32's four arms landed, the scope-exit managed-local release matrix still has holes: i386 releases no Variant, no promotable-int and no managed-record local; arm32 releases no promotable-int local. Each is a silent leak on every call to any routine holding one."
status: done
owner: claude-A
---

# The scope-exit release matrix still has four holes

- **Track A** (`EmitManagedLocalCleanupForTarget` in `compiler/ir_codegen.inc`).
- Split out 2026-08-21 from
  [[bug-a-riscv32-drops-interface-releases-in-six-shapes]], which closed
  riscv32's four.

## The matrix

Now that all six arms live in one procedure, the gaps read off in one grep:

| arm | x86-64 | i386 | arm32 | aarch64 | xtensa | riscv32 |
| --- | --- | --- | --- | --- | --- | --- |
| COM interface | yes | yes | yes | yes | — | yes |
| static array of managed | yes | yes | yes | yes | — | yes |
| ansistring | yes | yes | yes | yes | yes | yes |
| variant | yes | **NO** | yes | yes | — | yes |
| promotable int | yes | **NO** | **NO** | yes | — | yes |
| record w/ managed fields | yes | **NO** | yes | yes | — | yes |
| dynamic array | yes | yes | yes | yes | — | yes |

Four holes: i386 × {variant, promotable int, record}, arm32 × {promotable int}.

## Why it matters and why nothing catches it

A missing arm is a leak per call, and a leak prints nothing — which is how the
dyn-array arm stayed missing on four backends, how the static-array arm stayed
missing on three, and how riscv32's interface arm stayed missing on one. The
tests that catch these are the ones that COUNT destructor calls, and they are
wired into `test-core` (native) rather than the cross suites.

So the fix needs its own evidence: either a counting test built for a cross
target, or `-dPXX_HEAP_DEBUG` before/after.

## Where to start

Copy the arms from aarch64's block — it is the only cross target with all six —
translating the register moves. Each is 6-10 lines: address of the slot into the
first argument register, a descriptor into the second where the helper takes
one, `EmitCallProc`. The helpers (`PXXVarClear`, `PXXPromoClear`,
`PXXRecordRelease`) are ordinary Pascal and already exist.

xtensa's nearly-empty row is deliberately NOT in scope: its exception runtime
exists only under the Call0 ABI, so it is Track S.

## Gate

A counting test showing the freed count matching native under
`tools/run_target.sh` for i386 and arm32; self-host fixedpoint +
`tools/gate.sh quick`.

## Resolution (2026-08-21)

All four holes closed. The matrix now reads yes across every hosted target:

| arm | x86-64 | i386 | arm32 | aarch64 | xtensa | riscv32 |
| --- | --- | --- | --- | --- | --- | --- |
| COM interface | yes | yes | yes | yes | — | yes |
| static array of managed | yes | yes | yes | yes | — | yes |
| ansistring | yes | yes | yes | yes | yes | yes |
| variant | yes | **yes** | yes | yes | — | yes |
| promotable int | yes | **yes** | **yes** | yes | — | yes |
| record w/ managed fields | yes | **yes** | yes | yes | — | yes |
| dynamic array | yes | yes | yes | yes | — | yes |

Each added arm is aarch64's, translated: slot address into the first argument
register, descriptor into the second where the helper takes one, `EmitCallProc`.
The helpers (`PXXVarClear`, `PXXPromoClear`, `PXXRecordRelease`) already existed.

### The evidence problem, and what solved it

The ticket asked for "a counting test built for a cross target, or
`-dPXX_HEAP_DEBUG` before/after". Neither is available for these three arms:
counting needs a destructor, and a Variant, a record and a promotable int have
none. That is precisely why these holes lasted — every test that ever caught one
of these counted destructor calls, so only the class-shaped arms were ever
watched.

`test/test_managed_local_release_reuse.pas` counts nothing and **observes the
allocator** instead. pxx's free list hands a released block straight back for
the next same-sized request, so a routine that allocates one managed local per
call returns the SAME payload address every call — unless the local leaks, in
which case each call takes a fresh block and the address marches upward. First
call versus fortieth is the whole assertion: no destructor, no counter, no heap
instrumentation, and it works for every managed kind.

It reproduced the bug before the fix, which is the part that matters:

```
i386   before:  rec first=FALSE   var same=FALSE      (arm32/aarch64: TRUE)
i386   after:   ok 5 / 5          (native, arm32, aarch64: ok 5 / 5)
```

One trap worth recording: the first draft had the static-array round allocate
all THREE elements, and it failed on x86-64 with nothing leaked. The free list is
LIFO per size bin, so freeing three blocks and requesting three hands them back
reversed — the address differs every call. The probe is only valid with ONE
allocation per round.

Wired into the core list and the i386 / arm32 / aarch64 target blocks as an
output comparison against the x86-64 build, which is the right oracle here since
the arms differ per backend.

### Not covered

- **riscv32** cannot build the test: `target riscv32: unsupported node in IR
  codegen: var_store`, the wall tracked on
  [[bug-a-nilpy-on-cross-targets-four-remaining-walls]]. Its arms are all
  present (landed with [[bug-a-riscv32-drops-interface-releases-in-six-shapes]]);
  only the test is blocked.
- **The promotable-int arm is unproven by test on i386 and arm32.**
  `tyPromoInt32`/`tyPromoInt64` are NilPy's arbitrary-precision ints, so the leak
  needs a `.npy` program on a cross target, and NilPy has no way to express the
  address probe. The arm is a mechanical mirror of aarch64's and is stated here
  as mirrored-not-measured rather than claimed as verified.
- **xtensa's row** stays nearly empty: Track S.

## Gate

`tools/gate.sh quick` GREEN (self-host fixedpoint 103s).
`test_managed_local_release_reuse` = 5/5 on native, i386, arm32 and aarch64, and
FALSE→TRUE on i386 for the two arms that were missing. Cross-target breadth is
Track T's, against this sha.

## Log
- 2026-08-21 — resolved, commit 421ef927b.
