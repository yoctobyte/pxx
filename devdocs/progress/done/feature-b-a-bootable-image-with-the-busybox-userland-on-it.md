---
slug: feature-b-a-bootable-image-with-the-busybox-userland-on-it
title: "Rung 3: boot a kernel under qemu-system with the pxx-built busybox as its userland"
track: B
prio: 70
type: feature
status: done
created: 2026-09-02
found-by: frankD
owner: franks-ab
blocked-by: []
summary: "MET 2026-09-04. A 258-applet busybox built entirely by the PINNED v403 pxx (400 translation units, 400 objects, one link) boots under qemu-system-x86_64 as PID 1, and the proof is not a chroot and not eyeballed: the guest hashes /proc/1/exe and it equals the binary we shipped, and tools/busybox_diff.sh's own 621-case list -- EXTRACTED from that script rather than reimplemented -- runs INSIDE the guest and its transcript is byte-identical to the host gcc oracle, with a positive control asserting the comparison can still fail. Kernel: Alpine v3.21 netboot vmlinuz-virt, 6.12.81-0-virt, fetched not built. `tools/mkkiosk.sh --busybox=<bin> --cases=<work dir>` is the whole thing and prints KIOSK-BUSYBOX-COMPLETE. THE TICKET'S PREMISE WAS ALREADY STALE WHEN FILED: kernel-and-rootfs was settled by measurement on 2026-08-30 and mkkiosk.sh already booted a working image -- what was actually missing was that its PID 1 was DEBIAN'S busybox (`cp /usr/bin/busybox`), so the one line that mattered was tools/mkkiosk.sh:52. The image is dynamic, not static: -static is refused by bug-a-errno-is-one-global-across-all-threads-..., so it carries ld.so and libc. FOUND A SILENT MISCOMPILE ON THE WAY: bug-c-offsetof-in-a-static-array-initializer-folds-to-zero-silently, which the 621-case corpus is structurally unable to see because 516 of those cases are `applet --help`."
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


## Met, 2026-09-04 — what was run and what it proves

```
PXX=stable_linux_amd64/default/pinned tools/mkkiosk.sh \
    --busybox=<pxx-built busybox> --cases=<busybox_diff --keep work dir>

  cases: 258 applets, extracted from tools/busybox_diff.sh (a77c58d815bc)
  image: kernel 12M + initramfs 36M
    PID 1   sha256 ab28159146a5 == the busybox we built
    CONTROL cmp rejects a one-byte mutation of the same transcript
    PASS    in-guest transcript byte-identical to the host gcc oracle over 621 cases
  KIOSK-BUSYBOX-COMPLETE
```

**Which kernel, since the ticket asks:** Alpine v3.21 netboot `vmlinuz-virt`,
`6.12.81-0-virt`, fetched. The fetch-versus-build decision was already taken and
measured on 2026-08-30 and this rung did not reopen it.

**PID 1 is ours, asserted rather than described.** `/init` is a script, so PID 1's
`exe` is the interpreter — our busybox. The guest hashes `/proc/1/exe` itself and
the host compares that to the binary it shipped, so the claim fails loudly if the
image is ever built from something else.

**The transcript is compared, and the comparison can fail.** A `cmp` of two
transcripts is exactly the instrument this repo warns about — it prints PASS over
two names for one file just as happily — so the run flips one byte of the guest
transcript and requires `cmp` to reject it before it will report the real result.

**And with `--selfhost`, the owner's whole sentence runs on our own userland.**
`--busybox --selfhost` reaches `SELF-HOST FIXEDPOINT INSIDE THE VM: stage1 ==
stage2` in a VM where PID 1, the shell, and every tool are pxx-built — seeded by
the pinned v403 compiler against HEAD's `compiler.pas`. Previously that
fixedpoint ran under DEBIAN's busybox, so the compiler was the only pxx thing in
the image.

**That verdict is `cmp`, from the binary I had just found a miscompile in**, so
it was positive-controlled before being believed: our busybox's `cmp -s` on two
identical 10.2 MB files (a stage binary's size) returns 0, and returns 1 when
they differ in the LAST byte only. It is not a `cmp` that always agrees.

**Separately: the same run also boots the ordinary kiosk image on our busybox**
(`--busybox` without `--cases`): our busybox mounts `/proc`, `/sys` and `/dev`,
the in-VM pxx compiles and runs a Pascal program, and the kiosk app answers
`sum`, `primes` and `about`. That is rung 3's "boot to a userland" half; the
case list is its "compared, not eyeballed" half.

### Three things the host's busybox gave for free and ours does not

All three are busybox CONFIG artifacts, not pxx defects, and all three are
handled in `tools/mkkiosk.sh` with the reason written next to the code:

- **It is dynamic.** `--emit-obj` objects are linked with `gcc -o out obj/*.o`,
  which links dynamically, and `-static` is *refused*: `errno` is a non-TLS weak
  `.bss` object in every pxx object and `ld` will not match it against libc.a's
  TLS one. So the initramfs carries `ld-linux` and `libc.so.6`.
  [[bug-a-errno-is-one-global-across-all-threads-so-a-thread-reads-another-threads-failure]]
- **No `--install`.** `CONFIG_FEATURE_INSTALLER` is off, so `busybox --install -s`
  answers `applet not found`; the applet symlinks are made at stage time.
- **No `sh` and no `[`.** Both are real applets whose Config.in knob is spelled
  unlike the applet name (`SH_IS_ASH`, `TEST1`), so an applet list built from
  `busybox --list` cannot select them. `ash` is present and is what `init` uses.
  `[` gets a five-line shim, because it is the harness's own plumbing — bash
  supplies it on the host — and without it every one of the 621 cases carried a
  `[: not found` line.

### What this rung could NOT see, and it matters

**516 of the 621 cases are `applet --help`.** `run_dispatch_cases` runs every
applet twice, by argv[0] and through the multiplexer, and `--help` prints a
string literal. The remaining 105 cases exercise `cat`, `echo`, `ash` and a
coreutils set with real arguments — which is why the corpus is a real oracle at
all — but no widening of the APPLET list reaches behaviour that `--help` does
not touch.

Booting the thing found one such bug within a minute:
`uname -a` printed `Linux` eight times, because busybox reads `struct utsname`
through a `static const unsigned short utsname_offset[] = { offsetof(...), ... }`
and every offset was zero.
[[bug-c-offsetof-in-a-static-array-initializer-folds-to-zero-silently]] — filed,
reduced to a three-line repro, and NOT fixed here: Track B does not rebuild the
compiler.

**That is the argument for the next rung**, and it is a measurement rather than a
preference: running applets with arguments found a silent wrong-value miscompile
that 400 objects and 621 green cases did not.

**Cite frankc-af's instance rather than this one — it is strictly stronger.**
[[feature-c-corpus-busybox-394-applets]] (`fd456ed89`, the section headed *"AND
THAT GREEN IS THE MOST IMPORTANT NEGATIVE RESULT ON THIS TICKET"*): 374 applets,
506 objects, **853 cases byte-identical to the gcc oracle, GREEN** — on the same
binary whose `uname -a` printed `Linux` eight times. A wider, greener corpus,
equally blind, with the binary sha and the `uname --help` / `uname -a` pair side
by side. The 141 → 258 → 374 progression is the demonstration: raising the applet
count is the obvious response to "516 of 621 cases are `--help`", it was tried
twice, and it buys nothing this defect class can be seen from.

frankD landed the answer as `d0104ec8e` — a real-argument case group, RED on
purpose at the time — and turned up two constraints doing it: nothing in a
differential transcript may print its own `argv[0]` (three install dirs produced
two *correct* usage messages naming different paths, and the harness reported
"the two oracles disagree" with both being gcc builds of one source), and
determinism excludes mtimes, not just clocks.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 82edcc32c.
