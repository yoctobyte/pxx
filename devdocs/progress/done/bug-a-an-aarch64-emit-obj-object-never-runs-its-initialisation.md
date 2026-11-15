---
track: A
prio: 40
type: bug
blocked-by: []
summary: "An --emit-obj object for aarch64 (Linux, and the BSDs if let through) has no .init_array: the global initialisers, the units' initialization sections and the Pascal main body never run when a C program links it. The init/fini thunk is gated to x86-64 and i386, and the aarch64 entry code at offset 0 still stores sp as the argc block, which is wrong when a loader calls in."
status: done
owner: unassigned
---

# An aarch64 `--emit-obj` object never runs its initialisation

- **Type:** bug, **Track A** (`compiler/pasparser_prog.inc` EmitInitFiniThunks,
  the aarch64 entry stages in `compiler/compiler.pas`, `compiler/cparser.inc`
  ~16302 for the C frontend's twin).
- **Found 2026-11-15** while trying `--os=freebsd --target=aarch64 --emit-obj`
  (refused today; the refusal was lifted by hand to see why).

## Measured

`test/test_os_objlink.pas` built with `--os=freebsd --target=aarch64
--emit-obj`, linked by the FreeBSD/arm64 VM's own `cc` with
`test/test_os_objlink_main.c`:

| row | x86-64 (any kernel) | aarch64 |
| --- | --- | --- |
| `sum=` | 55 | 55 |
| `flag=` (set by the main body) | 4242 | **0** |
| `pxx_greet(7)` (strings, a class, WriteLn) | prints, 29 | **hangs** (blocked in read(0)) |

`readelf -S` on the object: no `.init_array`, no `.rela.init_array`. The
Linux aarch64 object (`--target=aarch64 --emit-obj`, no `--os`) has none
either, so this is not BSD-specific: Linux aarch64 objects have never run
their initialisers.

## Why

1. `pasparser_prog.inc` (~line 2943) emits `EmitInitFiniThunks` only for
   `EmitSharedMode or (EmitObjMode and x86-64 or i386)`. On aarch64 the body
   falls through to the exit path instead.
2. `EmitInitFiniThunks` itself is x86-only: a raw `ret` (`EmitAsmX64`) and a
   `call rel32` (`$E8`) to code offset 0. `EmitSharedThunkPrologue` and
   `EmitSharedThunkEpilogue` already have aarch64 arms (a 160-byte frame), and
   `writeELFRelX64General` already writes `.init_array` with
   `R_AARCH64_ABS64` (rAbs64 = 257) when `InitThunkOff >= 0`.
3. The aarch64 object's code at offset 0 is the executable's entry stage:
   `ldr w1, =slot; mov x0, sp; str x0, [x1]`, storing the initial sp as the
   argc block. Under an init_array call, sp is the loader's stack, not an
   argc block. On x86-64 the equivalent stages are skipped under
   `EmitObjMode or EmitSharedMode` (compiler.pas ~3772-3810); the aarch64
   one is not.

## What a fix needs

- An aarch64 `EmitInitFiniThunks`: after the body, a return path that does
  not depend on x30 surviving the body (the body makes calls, so a plain
  `ret` returns to wherever the last `bl` left lr). One way: the thunk saves
  sp in a BSS slot (or a callee-saved register the body provably leaves
  alone), branches to the body, and the fall-through restores sp and runs the
  thunk epilogue. Record the branch with `RecordCodeRefAtLink` (link 30 for a
  `bl`, 0 for a `b`) so `--dce` re-patches it right.
- Skip or neutralise the offset-0 sp store under `EmitObjMode` on aarch64.
- Lift the gate in pasparser_prog.inc and in the C frontend.
- Then lift the BSD refusal in compiler.pas (`--emit-obj` on aarch64 for
  FreeBSD/NetBSD/OpenBSD) and add an arm64 objlink row to the three
  `test-<bsd>-arm64` targets. `tools/vm/objlink.sh` needs an object-only
  mode (a `.so` is x86-64 only); its reference can be the x86-64 Linux object
  half, whose output is the same.

## How to check without the BSD VMs

There is no aarch64 cross gcc on plexus, but the FreeBSD/arm64 VM
(`PXX_FBSD_ARCH=aarch64 tools/vm/freebsd.sh`, port 2228, TCG: slow) has `cc`,
and a Linux aarch64 object can be checked the same way on any aarch64 Linux
box with gcc.

## Fixed 2026-11-15

`EmitInitFiniThunks` has an aarch64 arm: the init thunk runs the prologue,
stores sp in a BSS slot and branches (`b`, recorded with link 0) to code
offset 0; where the body falls off, sp comes back from the slot and the thunk
epilogue returns to the loader. The offset-0 sp store turned out harmless (the
x86-64 entry stores rsp the same way in an object). The gate in
pasparser_prog.inc takes aarch64.

Measured with `test/test_os_objlink.pas` + `test_os_objlink_main.c`:

- FreeBSD/arm64, the VM's `cc`: identical to the x86-64 Linux object half.
  The refusal is lifted for FreeBSD, and `make test-freebsd-arm64` links it
  (`tools/vm/objlink.sh` with `PXX_OBJLINK_OBJECT_ONLY=1`).
- NetBSD/arm64: the link fails, `R_AARCH64_ABS32` truncated: NetBSD puts text
  at 0x200100000 and the backend's data literals are 4 bytes. Still refused.
- OpenBSD/arm64: the PIE link refuses the text relocations; with `-nopie` the
  program links and takes SIGSEGV. Still refused.
- Linux aarch64: the object now carries `.init_array`, but there is no aarch64
  linker on plexus to run it.

What would open NetBSD and OpenBSD: PC-relative data addressing in the
aarch64 backend (adrp/add, or 8-byte literals with ABS64 and a PIC story).
