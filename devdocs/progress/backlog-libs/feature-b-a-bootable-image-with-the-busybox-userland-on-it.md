---
slug: feature-b-a-bootable-image-with-the-busybox-userland-on-it
title: "Rung 3: boot a kernel under qemu-system with the pxx-built busybox as its userland"
track: B
prio: 70
type: feature
status: backlog
created: 2026-09-02
found-by: frankD
owner: ""
blocked-by: []
summary: "Rung 3 of feature-busybox-kiosk-selfhosting-target, and the live one now that rungs 1, 2 and 2b are done: a 141-applet busybox built entirely by pxx, 265 objects, one real link with no `-Wl,-z,muldefs`, byte-identical to the gcc oracle over 387 cases (feature-c-corpus-busybox-141-applets-linked, met 2026-09-02; it superseded the 80-applet/149-object/261-case figure this ticket was filed with). x86-64 only -- aarch64 waits on an --emit-obj object writer. What is missing is a KERNEL and a ROOTFS, not more compiler work. qemu-system is installed for every pxx target plus /dev/kvm. The first decision is fetch-a-kernel versus build-one, and it should be made with a measurement rather than a preference. The proof this rung owes is a boot to a shell prompt with PID 1 being our busybox -- not a chroot, which proves nothing about the kernel interface."
---

# Rung 3 — the image

The userland exists and is proven:

```
tools/busybox_diff.sh --separate --applets "$(busybox --list)"
  ORACLE  gcc separate build, 265 objects (387 cases)
  PASS    x86_64   byte-identical to the gcc oracle over 387 cases
```

(This ticket was filed against the 80-applet / 149-object / 261-case run.
`feature-c-corpus-busybox-141-applets-linked` met a strictly larger bar the same
day -- 141 applets, 265 TUs, no `-Wl,-z,muldefs`, and the gcc build itself
agreeing with upstream's own separately-linked binary. The userland this rung
needs is therefore bigger than the one it was written for, not smaller.)

Nothing about that is a chroot claim. It is 149 objects linked into one
multiplexer that answers exactly as a gcc-built one does over 261 input cases.
What it has never done is come up as **PID 1 under a real kernel**, which is the
whole point of the rung: every proof so far runs under the host's kernel, and
qemu-user at that.

## The decision this rung opens with

**Fetch a kernel or build one.** Building is a large job and teaches nothing
about pxx; fetching is a download and a version to pin. Take the measurement
first — how long does a `make defconfig bzImage` actually take on plexus, and is
there a distribution kernel small enough to boot with a busybox initramfs
unmodified? Decide from those two numbers, not from taste.

Do the x86-64 image FIRST even though the cross axis is the interesting one:
`/dev/kvm` is present, so the loop is seconds rather than minutes, and every
mistake made here is one not made twice.

## What the rung must prove, and what would fake it

- **A boot to a shell prompt with our busybox as PID 1.** A chroot into the
  rootfs from the host proves the binary runs; it says nothing about the kernel
  interface, `/proc`, or init.
- **The transcript compared, not eyeballed.** The same case list
  `tools/busybox_diff.sh` already runs, executed inside the guest, diffed
  against the host oracle. A boot that reaches a prompt and is then declared
  working is the shape this repo keeps paying for.
- **Say which kernel and which config.** "It boots" without them is a claim
  nobody can reproduce.

## What is NOT in this rung

- Rung 4, the compiler self-hosting **inside** the image. Related and strictly
  stronger; keep them apart so a half-working image does not read as a
  self-host claim.
- Rung 5, the kiosk application — file it when this resolves, since its shape
  depends on what the image can do.
- The aarch64 separate build. That waits on
  [[feature-a-object-output-for-arm32-and-aarch64]] and is not this rung's
  business; an x86-64 image is a complete rung on its own.
