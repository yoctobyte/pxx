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
summary: "Owner-set target (2026-08-30): compile busybox, then stand up a qemu-system VM on some kernel/CPU running that busybox userland with a shell, the self-hosting pxx compiler, and a simple kiosk application. Umbrella only -- the work lives in the rungs below, each of which is filed or exists. HOST DEPENDENCY RESOLVED 2026-08-30: the owner granted sudo and qemu-system is now installed for EVERY pxx target -- aarch64, arm, riscv32, riscv64, xtensa, x86_64, i386 -- plus /dev/kvm. Rungs 1-2 (busybox) and rung 3 (image) can all proceed."
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
   `tools/busybox_cat_diff.sh`. Cost three compiler fixes and the aarch64
   `IR_ALLOCA` port; see the resolved ticket.
2. **busybox multi-applet + `ash`** — the shell half.
   `feature-c-corpus-busybox-multi-applet` [C]. `feature-eliah-shell` is
   `done/` and is our own shell, a separate artifact; this rung is busybox's.
   Rung 1 says explicitly what it does NOT establish: `cat` reaches 25 of
   libbb's ~145 TUs, and the ones it misses are where `pwd`/`grp`/`statfs`/
   `getrlimit` are actually called — stubs-by-omission today.
3. **qemu-system + a kernel.** **BLOCKED, and not on us** — see below.
4. **The compiler self-hosting *inside* the image.** Related and not identical:
   `bug-a-the-cross-self-host-proof-runs-a-different-configuration-than-the-native-one`.
   A self-host under a real kernel on a cross CPU is a strictly stronger claim
   than either current gate.
5. **The kiosk application** — not yet filed; file it when rung 3 resolves, since
   its shape depends on what the image can do.

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

**Still open, and NOT resolved by the install:** which kernel + rootfs. Building
a kernel is a large job; fetching one is a download. That is rung 3's first
decision and it should be made with a measurement, not a preference.

`decide-install-qemu-system-and-a-freebsd-image-on-plexus` [p55] asked for this
emulator **and** a FreeBSD image. **The emulator half is now done**; the
multi-GB FreeBSD image is a separate call and stays open.
