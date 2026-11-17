---
track: ESP
tags: [C, xtensa, emit-obj, shared-runtime, busybox, gibux]
prio: 20
type: feature
blocked-by: []
summary: "Several xtensa --shared-runtime objects plus the runtime object (built from pxx/runtime_all.h, which needed C setjmp on xtensa) now link with GNU ld and share one crtl: errno, stdout, environ and the heap are one across objects. The stdarg/setjmp copies every --shared-runtime object carries are WEAK (ObjEspProcBind), and C __attribute__((weak)) definitions are too, which these writers had dropped. Self-contained objects stay GLOBAL on purpose: the xtensa and riscv32 writers resolve calls inside an object at emit time, so weak crtl copies would link cleanly and keep one heap and one stdout per object."
status: done
owner: unassigned
---

# xtensa shared-runtime objects link

This is BusyBox on Gibux, built as one pxx object per translation unit (pxx2's item 3).

## Recipe
Each translation unit:

    pascal26 --target=xtensa --platform=posix --xtensa-soft-mulhigh --xtensa-abi=windowed --no-ro-data --shared-runtime --emit-obj tu.c tu.o

The runtime, once:

    printf '#include <pxx/runtime_all.h>\n' > rt.c
    pascal26 <same flags, without --shared-runtime> rt.c rt.o

Then:

    ld -pie --no-dynamic-linker -e app_main -T prog.ld *.o rt.o

`pascal26 --link` does not do this for xtensa yet: ElfLnkAddSharedRuntime knows x86-64 and aarch64 only. GNU ld does it.

## Why not the self-contained default (B)
On x86-64, B makes crtl WEAK, and callers reach the surviving copy through relocations. The xtensa and riscv32 writers resolve intra-object calls at emit time, so a losing weak copy would still serve its own object, with its own state. Those objects stay GLOBAL and fail loudly with `multiple definition`.

## Test
tools/check_xtensa_shared_runtime.py builds test/c_xtensa_srt_{main,part}.c and the runtime object, links them, and runs the result under qemu-xtensa. It checks:
- errno set in one object is read in the other
- both objects see the same stdout
- getenv works from the second object
- a malloc in one object is freed in the other
- varargs and setjmp work in both objects
- the exit status is right

It also requires the PIE link to succeed.
