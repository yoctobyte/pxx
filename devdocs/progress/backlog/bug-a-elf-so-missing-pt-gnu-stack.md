---
summary: "pxx-emitted .so has no PT_GNU_STACK, so glibc >= 2.41 refuses to dlopen it: cannot enable executable stack"
type: bug
track: A
prio: 60
---

# Emitted shared objects carry no `PT_GNU_STACK` — undlopenable on current glibc

- **Type:** bug (Track A — ELF emission)
- **Filed:** 2026-07-31 by Track T from the xeon watcher enrollment comparison.
- **Job:** `test-asm#src:test/test_asm_so.asm` — passes on borg, fails on xeon.

## Symptom

```
dlopen: /tmp/.../test_asm_so26.so: cannot enable executable stack as shared
        object requires: Invalid argument
test-asm: .so dlopen round-trip FAILED
```

The job's `readelf` assertions (`DYN`, `X86-64`, `NEEDED libc.so.6`) all pass.
It is the `dlopen`/`dlsym` round-trip at the end of the recipe that fails.

## Cause (measured, not inferred)

```
$ readelf -lW /tmp/asmso.so
  Type    Offset   VirtAddr           FileSiz  MemSiz   Flg  Align
  LOAD    0x000000 0x0000000000000000 0x0002b8 0x0002b8 RWE  0x200000
```

One `LOAD` segment, mapped **RWE**, and **no `PT_GNU_STACK` program header at
all**. Absent `PT_GNU_STACK`, the loader falls back to the historical default —
"this object requires an executable stack" — and calls the kernel to make the
thread stack executable. Modern glibc/kernels refuse that outright, so
`dlopen` returns the error above.

This is not qemu, not the test, and not the box's packages: it is what the
linker/ELF writer emits.

## Why it looked host-specific

| host | glibc | result |
|---|---|---|
| borg | older | permits enabling exec stack → job green |
| xeon | 2.43 (Ubuntu 15.2 / Linux 7.0.0) | refuses → job red |

So it is a **latent defect that only newer hosts surface**, not an xeon
environment gap. borg's green is the stale answer here. The blast radius is
wider than the test: *every* shared object pxx emits is currently
un-`dlopen`-able on an up-to-date distro.

## Fix

Emit a `PT_GNU_STACK` program header with flags `RW` (not `RWE`) for shared
objects — and ideally stop mapping the single `LOAD` segment `RWE` at all
(W^X: split `R E` text from `RW` data). The `PT_GNU_STACK` header alone fixes
the `dlopen` failure; the RWE `LOAD` is a separate hardening concern worth its
own look while the ELF writer is open.

## Repro

```sh
./compiler/pascal26 test/test_asm_so.asm /tmp/asmso.so
readelf -lW /tmp/asmso.so | grep GNU_STACK    # no output = the bug
tools/testmgr.py --tier full --job 'test-asm#src:test/test_asm_so.asm'
```

Track T filed this and does not fix it (T owns the tool, never the bug).
