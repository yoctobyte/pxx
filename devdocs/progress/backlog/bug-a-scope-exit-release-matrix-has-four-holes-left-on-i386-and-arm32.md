---
track: A
prio: 45
type: bug
blocked-by: []
summary: "After riscv32's four arms landed, the scope-exit managed-local release matrix still has holes: i386 releases no Variant, no promotable-int and no managed-record local; arm32 releases no promotable-int local. Each is a silent leak on every call to any routine holding one."
status: backlog
owner: ""
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
