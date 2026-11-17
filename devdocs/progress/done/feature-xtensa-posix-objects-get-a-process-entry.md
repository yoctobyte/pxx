---
track: ESP
tags: [C, xtensa, entry, gibux, busybox, pie]
prio: 20
type: feature
blocked-by: []
summary: "A windowed xtensa --platform=posix --emit-obj now has a process entry at .text+0 (GLOBAL app_main). It does entry sp,32, seeds the root frame's save area, stores the initial sp to BSS_INITIAL_RSP, runs __pxx_run_initializers (environ), calls main(argc, argv), runs the finalizers, and calls exit_group with main's result. Link with `ld -e app_main` (with -pie --no-dynamic-linker -T prog.ld for Gibux). Before this, offset 0 held an `ill`. In an object without main, app_main is WEAK."
status: done
owner: unassigned
---

# A process entry for windowed xtensa posix objects

BusyBox on Gibux (ESP32-S3) needs main(argc, argv) with environ. Both Gibux and Linux start a process as if by a CALL4 that never returns: PS.WOE=1, CALLINC=1, a0=0, and the Linux initial stack at sp.

## The stub
It is the call0 C entry stub's sequence one window over, with arguments in a10/a11. It comes from the cparser.inc object-mode arm, next to the IDF one.

The root frame's save area is seeded the way the Pascal process entry does it (EmitProgramEntryForTarget). Without that, main's result kept in a7 across the finalizer call came back 0, and every program exited 0. No CALL8 reached this frame, so [sp-12] was garbage, and the window overflow spilled a4..a7 through it.

## Weak app_main
In a posix object with no main, app_main is WEAK (ObjAppMainIsWeak), so it can't clash with the object that has the program's main.

Linking several self-contained xtensa objects still fails, but for another reason: crtl's routines are GLOBAL in each object (memcpy is defined more than once). That belongs with the xtensa shared-runtime work, pxx2's item 3.

## Also fixed
The IRAM writer's .rela.xt.lit (29c8ec11bb, feature-xtensa-objects-carry-a-literal-table) linked to section 9, .strtab, instead of 8, .symtab. So ld refused every literal of an object that goes through that writer, which this stub's object does.

## Test
tools/check_xtensa_posix_main.py:
- **Run:** links test/c_xtensa_posix_main.c with `ld -e app_main` and runs it under qemu-xtensa with an argument and an environment variable. It must print argc, argv[1], the variable and the atexit line, and exit 3. The old compiler gives no output and exit -4 (an illegal instruction at the `ill`).
- **PIE:** the same object must link as a PIE.
- **Weak:** an object without main must have a WEAK app_main.
