---
slug: feature-crtl-struct-stat-is-the-host-libc-layout-on-every-target
track: C
prio: 40
type: feature
status: open
found: 2026-11-28
found-by: pxx2
owner:
summary: "bug-crtl-struct-stat-is-not-glibc-s-layout-on-x86-64 matched struct stat to glibc on x86-64 only. On aarch64, riscv64, i386 and arm (and against musl), crtl keeps its own field order, which is fine for crtl's own programs and wrong for any --system-libs object handed to that libc's stat family. Match each target's asm-generic / arch stat layout from documented values, with a sizeof/offsetof test per target."
---

# struct stat as the host libc's layout on every target

x86-64 is done. The other targets need their layouts written from the
documented kernel ABI (asm-generic/stat.h for aarch64 and riscv64, the
i386/arm stat64 variants), not copied, each checked with an offsetof test
against that target's gcc where one is available.

Low priority: only `--emit-obj --system-libs` objects on those targets
are affected, and none is built today.
