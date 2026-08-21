---
track: A
prio: 60
type: bug
blocked-by: []
summary: "i386 SIGSEGVs (rc=139) on an interface `as`-cast temporary and on a single-pointer interface ABI shape. Four tests crash mid-output on i386 alone — arm32, aarch64, riscv32 and x86-64 all print the correct answer. A crash, not a wrong value, so it is loud; it is also the only cross target that dies."
status: backlog
owner: ""
---

# i386 segfaults on an interface as-cast temporary

- **Track A** (`compiler/ir_codegen386.inc` — the interface as-cast temp
  lifetime and the single-pointer interface ABI).
- Found 2026-08-21 by the 53-test dyn-array + interface cross differential.

## Measured

Four tests, i386 ONLY. Every other target (x86-64, arm32, aarch64, riscv32)
matches.

| test | i386 | others |
| --- | --- | --- |
| `test_interface_as_cast_retains` | **rc=139**, no output | 7/7 |
| `test_interface_ascast_temp_lifetime` | **rc=139** after `in P w=` | full output |
| `test_interface_mainbody_ascast_temp` | **rc=139** after `cast=` | `cast=107 / after nil / destroy 7` |
| `test_interface_single_pointer_abi_b337` | **rc=139** after `size-is-one-word: TRUE` | full output |

The first three all die at the point where an `as`-cast TEMPORARY is next
touched — the third gets as far as printing `cast=` and dies before the value.
The fourth dies at the second use of a single-word interface value. That is one
suspect, not four: an as-cast temp's slot on i386.

## Where to start

The three as-cast tests share the shape `(obj as IFoo)` producing a hidden
temp that must be retained for the expression's extent and released after. On
x86-64 that temp is a frame slot with a scope-exit release; check what i386's
IR_AS_CAST lowering does with the slot — in particular whether it writes a
handle into a slot the epilogue then releases at a DIFFERENT width, since i386's
"fat slot" model lays out 8-byte slots and reads only the low 4 bytes.

`test_interface_mainbody_ascast_temp` is the cheapest repro: it is a main-body
program, it prints one line before dying, and the line it prints is correct.

Do not reason about the slot — dump it. `PXXDBG=a.ir:<proc>` for the three that
have a proc, and `-g -O2` + gdb under qemu-i386 for the main-body one; the
playbook is `devdocs/dev/debugging-playbook.md`.

## Gate

All four tests matching the native output under `tools/run_target.sh i386`; the
53-test dyn-array + interface cross differential no worse than baseline;
self-host fixedpoint + `tools/gate.sh quick`.
