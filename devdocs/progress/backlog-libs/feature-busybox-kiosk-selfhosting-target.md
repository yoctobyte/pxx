---
slug: feature-busybox-kiosk-selfhosting-target
title: "A bootable image: busybox userland + shell + the self-hosting compiler, running a kiosk app under qemu-system"
track: B
prio: 80
type: feature
blocked-by: []
status: new
created: 2026-08-30
owner: ""
summary: "Owner-set target (2026-08-30): compile busybox, then stand up a qemu-system VM on some kernel/CPU running that busybox userland with a shell, the self-hosting pxx compiler, and a simple kiosk application. Umbrella only -- claim a rung. RUNGS 1, 2, 2b AND 3 ARE DONE. As of 2026-09-04 the userland is 258 APPLETS built busybox's own way -- 400 translation units, 400 objects, one real link, 621 cases byte-identical to the gcc oracle on x86-64 (`tools/busybox_diff.sh --separate`) -- and it BOOTS AS PID 1 under qemu-system-x86_64 with that same case list re-run inside the guest and compared byte for byte (`tools/mkkiosk.sh --busybox= --cases=`, feature-b-a-bootable-image-...). With --selfhost it reaches a SELF-HOST FIXEDPOINT INSIDE THAT VM (stage1 == stage2, seeded by pinned v403 against HEAD sources), and the kiosk app answers, so the owner's sentence -- busybox userland, shell, self-hosting compiler, kiosk app -- is met end to end on x86-64 with every one of those built by pxx. aarch64 is proven at 26 applets by unity build and still waits on an --emit-obj object writer. WHAT IS OPEN is no longer kernel-or-rootfs (settled by measurement 2026-08-30): it is aarch64, and running applets with REAL ARGUMENTS. That last is a measurement, not a ratio (feature-c-corpus-busybox-394-applets): frankc-af's 374-applet corpus -- 506 objects, 853 cases BYTE-IDENTICAL to the gcc oracle, GREEN -- was green on the same binary whose `uname -a` printed `Linux` eight times, because the corpus invokes applets with `--help` and `--help` prints a string literal. A wider, greener corpus, equally blind. The miscompile behind it (bug-c-offsetof-in-a-static-array-initializer-folds-to-zero-silently) is FIXED in 62463923f; the blindness that hid it is not, and frankD's real-argument case group (d0104ec8e) is the answer to it."
---

# The target, in the owner's words

> *"compile busybox. then, we can have a qemu with random kernel on random cpu
> with busybox with shell and self-hosting compiler running a simple kiosk
> application."*

This is an **umbrella**. Do not claim it — claim a rung. It exists so the rungs
inherit the owner's priority through the dependency edges, and so nobody
re-derives the decomposition.

## Why this target is worth its rank

It is the first thing that would exercise **the whole stack end to end at once**:
the C frontend on real syscall-heavy source, `crtl` (the thin layer), the
self-host, a cross target, and the runtime under a real kernel rather than
qemu-user. Every existing corpus proves one layer. This proves they compose.

## The rungs, in order

1. **busybox `cat`, standalone** — ~~`feature-c-corpus-busybox-applet`~~
   **DONE 2026-08-31.** Byte-identical to a gcc-built binary across 12 input
   cases on x86-64 AND aarch64 under `tools/run_target.sh`, and equal to
   upstream's own separately-linked `busybox_CAT`. Repeatable:
   `tools/busybox_diff.sh --applets cat`. Cost three compiler fixes and the aarch64
   `IR_ALLOCA` port; see the resolved ticket.
2. **busybox multi-applet + `ash`** — the shell half. **DONE 2026-09-01** at
   twelve applets, 61 translation units, 114 cases, byte-identical to the gcc
   oracle on x86-64 AND aarch64. Cost fifteen compiler/runtime fixes, every one
   found by ATTEMPTING the target.

   **2b. The userland, built busybox's own way — DONE 2026-09-02.**
   `feature-c-corpus-busybox-userland-by-separate-compilation` [C] dropped the
   unity for separate compilation, and then the applet set kept going:

   | | applets | TUs | objects | cases |
   | --- | --- | --- | --- | --- |
   | rung 2 (unity) | 12 | 61 | — | 114 |
   | unity, widened | 26 | 82 | — | 154 |
   | **separate** | **80** | **149** | **149** | **261** |

   All byte-identical to the gcc oracle, which now builds separately too — a
   unity oracle would have capped this mode at the unity's own ceiling, and
   that ceiling is gcc's rather than pxx's (busybox's `struct globals` pattern
   is one namespace claim per applet).

   Getting from 12 to 80 cost, all found by attempting it and all closed:
   `x & 0` never folding a constant-false branch; `sizeof` yielding a fixed
   64-bit type where `size_t` is pointer-width; the `#if` evaluator being
   purely signed where C99 6.10.1 wants intmax_t/uintmax_t; a macro call being
   silently mis-expanded past sixteen arguments (and hanging the compiler on
   busybox's own `factor.c`); `static` on a C function being ignored by the
   object writer; crtl being defined globally in every object (frankA); and
   sixteen crtl gaps enumerated in one measured pass.

   **x86-64 only for the separate build** — `--emit-obj` has no object writer
   for aarch64 ([[feature-a-object-output-for-arm32-and-aarch64]]). aarch64 is
   proven at 26 applets by unity build, which is the honest cross claim today.
   `feature-c-corpus-busybox-multi-applet` [C]. **FIRST BAR MET 2026-09-01**
   (`2789f87a7`): cat+echo+the multiplexer, `NUM_APPLETS 2` with the dispatch
   table compiled IN, byte-identical to gcc over 28 cases on x86-64 and
   aarch64, argv[0] and `busybox <applet>` both. Cost one compiler fix — a
   constant left operand of `&&`/`||` survived every `-O` level including
   `-O3` (`88ef1232f`). **The `ash`-and-TU-surface caveat that used to close
   this paragraph — "still open, which is why the rung is not resolved" — is
   spent:** `ash` is in the 258-applet set, the TU surface is 400 of libbb's
   ~145-plus-applets rather than 28, and all three rung-1/2 tickets are in
   `done/`. `feature-eliah-shell` is
   `done/` and is our own shell, a separate artifact; this rung is busybox's.
   Rung 1 says explicitly what it does NOT establish: `cat` reaches 25 of
   libbb's ~145 TUs, and the ones it misses are where `pwd`/`grp`/`statfs`/
   `getrlimit` are actually called — stubs-by-omission today.
3. **qemu-system + a kernel.** **DONE 2026-09-04**,
   [[feature-b-a-bootable-image-with-the-busybox-userland-on-it]]. The
   258-applet pxx busybox is PID 1 (the guest hashes `/proc/1/exe`) and the
   621-case list runs inside the guest byte-identical to the host gcc oracle.
   Kernel: Alpine v3.21 `vmlinuz-virt`, 6.12.81-0-virt, fetched.
   `tools/mkkiosk.sh --busybox= --cases=`.
4. **The compiler self-hosting *inside* the image.** **x86-64 half DONE the same
   day** — `--busybox --selfhost` reaches `stage1 == stage2` in a VM where PID 1,
   the shell and every tool are pxx-built. **The cross-CPU half is what is left**,
   and it is the strictly stronger claim: blocked on
   [[feature-a-object-output-for-arm32-and-aarch64]] (no aarch64 `--emit-obj`, so
   no aarch64 busybox) and on
   `bug-a-the-compiler-cannot-cross-build-itself-for-aarch64`. Related and not
   identical:
   `bug-a-the-cross-self-host-proof-runs-a-different-configuration-than-the-native-one`.
5. **The kiosk application** — **MET on x86-64, and deliberately NOT filed.**
   `examples/kiosk.pas` is pxx-built, ships in the image, and answers `about`,
   `sum N` and `primes N` in the booted VM. The rung was left unfiled until the
   image existed because its shape depended on what the image could do; the
   image can do it, so there is no work here to coordinate, rank or remember.
   A ticket would be bookkeeping for something already true.

## Host dependency: RESOLVED 2026-08-30

The owner granted sudo and **`qemu-system` is installed**, verified running
(10.2.1). Coverage is better than the target needs — **every pxx backend has a
system emulator**:

    qemu-system-aarch64  qemu-system-arm      qemu-system-riscv32
    qemu-system-riscv64  qemu-system-xtensa   qemu-system-x86_64  qemu-system-i386

`/dev/kvm` is present, so the x86-64 image runs at native speed and the cross
images run emulated. **"Random kernel on random CPU" is now a real choice rather
than an aspiration** — and `qemu-system-xtensa` in particular is new ground for
Track S, which had qemu-user only.

**Kernel + rootfs: SETTLED**, by measurement on 2026-08-30 and unchanged by
rung 3 — fetch Alpine's netboot `vmlinuz-virt` (12 MB, one second) rather than
build one (hours, and it teaches nothing about pxx). No rootfs at all on x86-64:
an initramfs of our own binaries plus, since the pxx busybox is dynamic, `ld.so`
and `libc`. This paragraph read as open for three days after it was closed, and
rung 3 was filed against it — the actual gap was one line of `tools/mkkiosk.sh`
booting DEBIAN's busybox as PID 1.

`decide-install-qemu-system-and-a-freebsd-image-on-plexus` [p55] asked for this
emulator **and** a FreeBSD image. **The emulator half is now done**; the
multi-GB FreeBSD image is a separate call and stays open.
