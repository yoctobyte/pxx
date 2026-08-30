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
summary: "Owner-set target (2026-08-30): compile busybox, then stand up a qemu-system VM on some kernel/CPU running that busybox userland with a shell, the self-hosting pxx compiler, and a simple kiosk application. Umbrella only -- the work lives in the rungs below, each of which is filed or exists. ONE host dependency the fleet cannot satisfy: qemu-system is NOT installed (only qemu-user), see decide-install-qemu-system-and-a-freebsd-image-on-plexus."
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

1. **busybox `cat`, standalone** — `feature-c-corpus-busybox-applet` [C, p60,
   `blocked-by: []`]. Unblocked 2026-08-30 by `1672aeaad`; `libbb.h` compiles and
   the 145 TUs are reachable. Residue is busybox's own `libbb` symbols, not crtl
   gaps. Bar: output byte-identical to a gcc-built `cat` under
   `tools/run_target.sh`, x86-64 + aarch64.
2. **busybox multi-applet + `ash`** — the shell half. `feature-eliah-shell` is
   `done/` and is our own shell, a separate artifact; this rung is busybox's.
3. **qemu-system + a kernel.** **BLOCKED, and not on us** — see below.
4. **The compiler self-hosting *inside* the image.** Related and not identical:
   `bug-a-the-cross-self-host-proof-runs-a-different-configuration-than-the-native-one`.
   A self-host under a real kernel on a cross CPU is a strictly stronger claim
   than either current gate.
5. **The kiosk application** — not yet filed; file it when rung 3 resolves, since
   its shape depends on what the image can do.

## The one thing the fleet cannot do

**`qemu-system` is not installed on this box** — `ls /usr/bin/qemu-system-*`
returns nothing; only qemu-user is present, which is what `tools/run_target.sh`
drives. Rungs 3-5 cannot start without it, and installing a system emulator plus
fetching a kernel/rootfs is a change to the owner's workstation.

`decide-install-qemu-system-and-a-freebsd-image-on-plexus` [p55] already asks
this for the FreeBSD port. **Same host dependency, second consumer** — worth
answering once for both, and the answer now unblocks more than it did when filed.

**Rungs 1 and 2 need none of it.** Start there.
