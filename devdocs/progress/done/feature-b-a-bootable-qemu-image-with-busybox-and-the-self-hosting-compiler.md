---
slug: feature-b-a-bootable-qemu-image-with-busybox-and-the-self-hosting-compiler
track: B
prio: 80
type: feature
status: done
owner: frankB
blocked-by: []
summary: "Rung 3 of feature-busybox-kiosk-selfhosting-target, DONE 2026-08-30, and it reaches rung 4 as well. `tools/mkkiosk.sh` builds a 15MB bootable image (fetched 12MB kernel + 4.7MB initramfs) that boots under KVM in ~2s running busybox userland, a pxx-built kiosk app, and pascal26 compiling Pascal INSIDE the vm. With --selfhost (7.5MB initramfs) it reaches a SELF-HOST FIXEDPOINT INSIDE THE VM in 40s end-to-end: stage1 == stage2, identical md5. The kernel/rootfs decision was settled by measurement, not preference: pascal26 and everything it emits are STATICALLY LINKED, so no distro rootfs is needed at all -- kernel + initramfs of static binaries is complete."
---

# A bootable image: busybox + the self-hosting compiler, under qemu-system

`tools/mkkiosk.sh` — `--selfhost` adds the compiler sources, `--interactive`
drops to the kiosk prompt and then a shell instead of running a scripted session.

## The decision the umbrella asked for, made by measurement

**Which kernel + rootfs.** Answered in two parts, and the first part deletes most
of the question:

**No rootfs is needed.** `file compiler/pascal26` says *statically linked*, and so
is every binary it emits. So the image needs no libc, no dynamic loader, no distro
userland — a kernel plus an initramfs of static binaries is a complete system.
That is why this is 15 MB and 2 seconds rather than a distro image. Had the
compiler been dynamically linked this rung would have been a rootfs project.

**The kernel is fetched, not built.** Measured: 12 MB, **1 second**. Building one
is hours. The host's own `/boot/vmlinuz` is `0600` root-only, so the zero-download
path needs sudo and buys nothing. Re-decide per target if a cross image needs one —
`qemu-system` is installed for every pxx backend.

## Measured

Host: qemu 10.2.1, `/dev/kvm` readable by the agent user (no sudo needed to run).

| | |
| --- | --- |
| kernel (Alpine `vmlinuz-virt`, 6.12.81) | 12 MB, 1 s to fetch |
| initramfs, default | 4.7 MB |
| initramfs, `--selfhost` | 7.5 MB |
| boot → kiosk → poweroff | **~2 s** |
| boot → **in-vm self-host fixedpoint** → poweroff | **40 s** end to end |

```
=== pxx kiosk: kernel 6.12.81-0-virt on x86_64 ===
ok: /bin/hello  [code=65304B ...]
compiled inside the vm
ok: ./pascal26.stage1  [code=9752344B  data=461168B  bss=100985812B  procs=3782]
ok: ./pascal26.stage2  [code=9752344B  data=461168B  bss=100985812B  procs=3782]
SELF-HOST FIXEDPOINT INSIDE THE VM: stage1 == stage2
kiosk> sum 1..100 = 5050
kiosk> primes below 1000 = 168
```

## Rung 4 is reached, and the claim wants stating precisely

The umbrella's rung 4 is *"the compiler self-hosting inside the image"*. That is
what `SELF-HOST FIXEDPOINT INSIDE THE VM` is: pascal26 compiled `compiler.pas` to
stage1, stage1 compiled it to stage2, and `cmp` says they are byte-identical
(md5 `a90ea54b948d82c4c20202df4fe49d96`).

**What this is NOT**, because the claims-discipline rule applies: this is x86-64
under KVM, i.e. the *native* architecture on a different kernel and userland. It
is **not** the cross-CPU self-host that
[[bug-a-the-cross-self-host-proof-runs-a-different-configuration-than-the-native-one]]
is about. Running it under `qemu-system-aarch64` without KVM is the next step and
is a strictly stronger claim; the script is x86-64 only today.

## Three facts worth not re-deriving

1. **The compiler resolves units relative to its own binary** (`<bindir>/../lib/rtl`,
   `<bindir>/builtin`). A stage built into `/tmp` looks for `/tmp/../lib/rtl` and
   fails with `unit source not found`. Every stage must live beside the sources.
   Cost one boot to find.
2. **`Makefile:22` names the full unit payload** —
   `compiler/*.inc + compiler/builtin/*.pas + lib/rtl/*.pas + lib/asmcore/*.pas`.
   `lib/asmcore` is the one that is easy to miss and is not under `compiler/`.
3. **An initramfs needs `/tmp` to exist.** It is not created for you, and the
   failure surfaces as `sh: not found` for a binary that was just built
   successfully — which reads like a linkage problem and is not one.

## Gate

`make lib-test` is unaffected (nothing in `lib/` changed). The artifact is
verified by running it: both modes reproduced end-to-end from the committed
script, output above.
