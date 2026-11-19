---
slug: feature-c-i386-link-for-c-objects
track: C
prio: 60
type: feature
status: done
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [c-frontend, toybox]
blocked-by: []
owner: claude-dupwt
summary: "`--link` is x86-64/aarch64 only ('the i386 object writer is a different format'), so toybox compiles all 205 units for i386 but cannot link. Options: i386 --link, or an i386 entry stub (like tools/pxx_freestanding_start.s: TCB in gs, init/fini arrays, environ) plus host `ld -m elf_i386`. pixx-f2 wants an i386 toybox."
---

# i386 link for C objects

Blocks the i386 half of feature-c-toybox-builds-with-pxx.


# Done 2026-11-19 (claude-dupwt): option B, entry stub + host ld

`tools/pxx_link_i386.sh -o OUT a.o b.o ...` assembles tools/pxxcrt_i386.S and
runs `ld -m elf_i386 -nostdlib -static`. pxx's objects carry their own crtl,
so no libc is involved. The stub provides argc/argv/envp, the .init_array
walk with (argc, argv, envp), and exit(main's result) through crtl's `exit`.
A raw exit syscall, as the x86-64 pxxcrt does, measurably lost atexit
handlers and buffered stdout. The stub does not install the pxx thread
block: a pxx object keeps errno as a plain global on x86-64 under gcc as
well (c_errno_is_per_thread says SHARED for both), so this is parity, and
the block's size is per-compile, so a hand copy would go stale.

`pascal26 --link` itself stays ELF64-only; porting the in-house linker to
ELF32 REL is the remaining option A, not needed for toybox.

## Measured

- test/c_i386_link_entry.c (row i386/c_i386lnk in test-i386): output and
  exit code equal the same file built as a pxx i386 program.
- toybox 0.8.15: all 205 units built with --target=i386 --emit-obj (0
  failures), linked by the script in 0.6 s. The binary is 167 MB, because
  each object carries crtl and i386 objects have no --function-sections, so
  ld cannot drop the copies. Applets checked by hand: echo, wc, basename,
  sort, seq, md5sum (equals the host's), ls, uname, true/false exit codes.
- toybox's own suite (scripts/test.sh on that binary): **1498 pass, 106
  fail, 24 skip**. The x86-64 pxx build gives 1502 / 102 / 24 (s6_rump);
  gcc passes 1604.
  - i386 only: cpio "archive length" and "-L"; devmem read/write 8 (6
    tests, 8-byte accesses on a 32-bit target).
  - x86-64 only: id 0, id root, id -G root, id -nG root (these pass on i386).
  Not chased here. The size is the obvious next step (function sections in
  the i386 object writer); see also
  bug-c-a-strong-definition-does-not-replace-a-weak-one-in-an-i386-object.
