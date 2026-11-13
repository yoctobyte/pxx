---
track: C
tags: [C, crtl, aarch64, i386, arm32, dropbear]
prio: 40
type: bug
blocked-by: []
summary: "crtl declared prctl as five fixed longs, where glibc declares it variadic: int prctl(int option, ...). dropbear's svr-main.c calls prctl(PR_SET_NAME, name, 0, 0) with four arguments. On aarch64, i386 and arm32 the external-call marshalling counts arguments against the prototype, so that TU failed to compile, with a message that named neither the callee nor the counts. On x86-64 it compiled with no diagnostic. prctl is now variadic and reads four longs, as glibc's wrapper does. The count error now names the callee and both numbers."
status: done
owner: unassigned
---

# crtl's prctl was fixed-arity, so a short call failed off x86-64

Found building dropbear for aarch64 ([[feature-c-dropbear-builds-with-pxx]],
acceptance 5): `src/svr-main.c` failed with

    pascal26:97: error: target aarch64: external call argument count mismatch
      near:       >>> static  main_inetd

The line and "near" point at the start of a function: codegen runs per
procedure, after the parse. Nothing in the message said which call it was.
Dropping each statement of `main_inetd` in turn did not move it. The
message now reads

    target aarch64: call to prctl passes 4 arguments, but it takes 5

and the same wording is used on i386 and arm32.

## Cause

`lib/crtl/include/sys/prctl.h` declared

    int prctl(int option, unsigned long arg2, unsigned long arg3,
              unsigned long arg4, unsigned long arg5);

Its comment argued that a variadic declaration "would buy nothing a caller
can see". glibc's is `int prctl(int option, ...)`, and callers pass what the
option needs. dropbear passes four. On x86-64 the short call compiled
silently, leaving arg5 as whatever was in r8. The AAPCS/cdecl marshalling on
the other three targets checks the count and refused it.

## Fix

- `prctl` is variadic. The body reads four `unsigned long`s with `va_arg`
  and passes them to the syscall: the same thing glibc's wrapper does. The
  kernel reads only the arguments the option defines.
- The header comment now says why.
- The argument-count error on aarch64, i386 and arm32 names the callee and
  both counts.

## Test

`test/c_crtl_telnet_and_prctl.c` now calls `prctl` with four arguments
(dropbear's shape) and with two. The c_telprctl26 row runs it on x86-64, and
the new c_telprctl26_a64 row compiles it with `--target=aarch64` and runs it
under qemu. Both set the name and read it back (`9 0 pxxprobe`). Checked by
hand on i386 and arm32 too.
