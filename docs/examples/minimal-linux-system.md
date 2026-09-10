---
title: A minimal Linux system
order: 56
---

# A minimal Linux system

PXX builds a bootable system whose entire userland is its own output: a Linux
kernel, a BusyBox shell compiled by PXX, and the PXX compiler itself, on one
ISO that boots both legacy BIOS and UEFI.

```sh
tools/busybox_diff.sh --separate --keep --targets x86_64 \
  --applets "ash cat echo ls mkdir cp mv rm pwd uname sleep mount umount dmesg sync ps date wc grep"
tools/link_freestanding.sh <that run's work dir>/obj -o /tmp/busybox
tools/mkminimal.sh --busybox=/tmp/busybox --iso --boot
```

Those three commands are a differential build of BusyBox, a freestanding link,
and the image. The build is **x86-64 only** today, and that is an absence rather
than a failure: no i386 or AArch64 image has been built.

Besides the ISO tools [described below](#reproducing-it-under-virtualbox), the
build needs a BusyBox source tree
(`tools/install_lib_candidates.sh busybox`), `binutils` for `as` and `ld`,
network access to fetch the kernel, and **GCC** — the first command is a
differential against a GCC build of the same sources, so without it there is no
reference and no result. Note also that `tools/mkminimal.sh` defaults to
`compiler/pascal26`, the compiler in your own checkout, rather than the pinned
stable one; pass `PXX=` to choose.

What you get, booted:

```
  pxx minimal system -- Linux 6.12.81-0-virt
  shell:    /bin/ash (busybox)
  compiler: pascal26 at /opt/pxx/compiler

BusyBox v1.36.1 (pxx-diff) built-in shell (ash)
# cat > h.pas
program h; begin writeln('hi'); end.
# pascal26 h.pas h && ./h
ok: h  [code=69400B  data=4184B  bss=46600B  procs=145]
hi
```

## What is in the image

| | |
| --- | --- |
| Linux kernel | Alpine's prebuilt `vmlinuz-virt`, **not** built by PXX |
| `/bin/busybox` | compiled by PXX, linked with no C library |
| `/opt/pxx` | `pascal26`, its builtin units, and the `rtl`, `asmcore` and `crtl` library trees |

Nothing else. No window system, no init system, no package manager, no libc.
`/init` mounts `/proc`, `/sys` and `/dev` and execs the shell.

The library trees are there because a compiler without them is half-installed
rather than smaller. Both frontends work on the image: Pascal, and C —
`#include <stdio.h>` resolves to PXX's own headers and links PXX's own C runtime,
so a C program built on the image is static and needs nothing the image does not
have. Measured inside the guest, because the host cannot answer it: a developer
box resolves `<stdio.h>` from `/usr/include` and will tell you a half-installed
image works.

If you assemble your own image, ship **all** of `lib/crtl` rather than just its
`include/`. There are three states and the middle one is a trap: with no `crtl`
at all a header-free C program still builds, because part of the runtime is baked
into the compiler; with `include/` only, the program compiles — with a
`crtl does not define puts` warning — comes out *dynamic*, and then fails at run
time with `ash: /tmp/u: not found`, which is an ENOENT about the missing
interpreter and reads as a missing file. Only the whole tree gives you a static
binary.

## What this does and does not establish

These are three separate claims, and they are worth keeping apart.

**PXX compiles BusyBox.** Specifically: a 19-applet configuration of BusyBox
1.36.1 **including the `ash` shell**, as 86 separate translation units, the way
BusyBox's own build compiles it. The test is differential —
`tools/busybox_diff.sh` builds the identical translation units with GCC and
compares both binaries' output across 132 cases, and PXX's is byte-identical.
This is a claim about a configuration, not about all 394 applets.

**The userland links no external library.** `tools/link_freestanding.sh` links
those objects with `ld` and a small entry stub into a static executable with no
`PT_INTERP`; `ldd` reports *not a dynamic executable*, and the assembled image
contains zero shared libraries. The C library is PXX's own `lib/crtl`, compiled
in from source. Note what is external and what is not: the **build** uses `ld`
and `as`, which are tools, not libraries — nothing is linked in from outside the
checkout, and the running system loads nothing.

**The kernel is not ours.** PXX does not compile Linux. The image boots a
distribution kernel, and "minimal Linux system" means a minimal *userland* on a
stock kernel.

## What it depends on

The interesting part of this image is what is *not* in the list. To rebuild the
userland you need PXX's source and BusyBox's source; to run it you need a kernel.

| To | You need |
| --- | --- |
| **run the system** | the kernel and this image — no libc, no dynamic loader, no distribution userland, nothing fetched at boot |
| **rebuild the userland from source** | PXX's own source, BusyBox's source, and `as` and `ld` from binutils |
| **rebuild the kernel** | not us: the image boots a prebuilt distribution kernel |
| **re-run the differential** | GCC, as the test's reference build — an oracle, not a build input |

Binutils is on that list for one reason, worth naming rather than hiding: PXX
cannot yet consume an object file, so the 86 BusyBox objects are combined by
`ld`, and `as` assembles the entry stub (`tools/pxx_freestanding_start.s`, which
is our own source). Everything *compiled* is compiled by PXX. Those two are
tools rather than libraries — nothing from outside the checkout ends up inside
the result, which is the claim the freestanding link asserts.

On licensing, since a self-contained image invites the question: everything PXX
contributes is MPL-2.0 (compiler) and zlib (runtime and libraries), so it imposes
nothing on what you build. The two third-party components are both GPL — the
Linux kernel, and BusyBox 1.36.1, which is GPL-2.0-**only**. See
[Licensing](../reference/licensing.md) for PXX's own terms.

## Reproducing it under VirtualBox

The ISO is a BIOS+EFI hybrid, so one file boots either firmware. Both paths are
verified under QEMU — SeaBIOS for legacy BIOS and OVMF for UEFI. VirtualBox
presents the same two firmwares and is expected to boot it unchanged, but that
has not been measured here; if you try it, attach the ISO as an optical drive and
leave the chipset defaults alone.

Building the ISO needs `xorriso`, `mtools` **and both GRUB platforms**
(`grub-pc-bin`, `grub-efi-amd64-bin`). With only the EFI platform installed,
`grub-mkrescue` still succeeds and writes an EFI-only boot catalog, which then
fails on BIOS firmware with `Could not read from CDROM (code 0009)` — a message
that reads like a corrupt image rather than a missing package.
`tools/mkminimal.sh` checks for both and refuses early.

## Size, honestly

The ISO is about 34 MB:

| | bytes |
| --- | --- |
| kernel | 11,695,104 |
| initramfs (compressed) | 9,736,189 |
| GRUB and ISO padding | 13,200,387 |

The BusyBox binary is 31 MB of the uncompressed payload, and **that is a known
defect rather than a cost of the approach.** BusyBox's own GCC build of the same
19 applets is 117 KB. The difference is that PXX currently emits each object with
a private copy of its runtime in a single `.text` section, so the linker cannot
discard the 85 redundant copies — the 86 objects' `.text` sums to within 824
bytes of the linked binary's. The fix is per-function sections, which lets
`ld --gc-sections` drop them; `--function-sections` already does the
relocation half of that work. Expect the binary to fall to well under a megabyte
when that lands.

Measured 2026-09-10 from the shipped image at commit `a3829fce2`. The three rows
sum to the ISO byte for byte, and the BusyBox figure was read out of the image's
own payload rather than off a build log. **Expect every figure here to move** —
this table was rewritten within the hour of first being published, because
shipping all of `lib/crtl` for the C frontend grew the initramfs by 439 KB. Only
the kernel is fixed. Re-run the three commands above and read your own numbers;
that is the check.

## Known limits

- The applet set is the one the differential was measured on, so there is no
  `test` or `[` builtin (use `case` for conditionals), no `head`, and no
  `poweroff` — shut down with `echo o > /proc/sysrq-trigger`. Line editing is
  off, so there is no command history at the prompt.
- **No networking.** No `ip`, `ifconfig` or `udhcpc` applet is built in, and
  `/init` configures no interface.
- **The system contains its compiler but does not reproduce itself.** It
  compiles and runs Pascal — measured both in batch and interactively at the
  serial console — but there is no self-host fixed point on this ISO, because it
  deliberately ships **no compiler sources**. `/opt/pxx/compiler` holds the
  `pascal26` binary and its builtin units and *zero* `.pas` or `.inc` files.
  Nor can it rebuild its own BusyBox: PXX cannot consume an object file, and the
  image carries no assembler and no linker.
- **The self-host fixed point in a VM is a different image.**
  `tools/mkkiosk.sh --selfhost` builds a larger development image that *does*
  carry the compiler's own sources, and there the compiler rebuilds itself
  inside the guest to a byte-identical second stage. Keep the two apart: *the
  compiler runs on the minimal ISO* and *the compiler reproduces itself in a VM*
  are separate claims, proved on separate images. This page is only the first.
- `/dev/console` is the serial port, which is what a headless `qemu -nographic`
  or `-cdrom` run wants. In a graphical VM window you will see kernel messages
  but the shell will be on the serial line.
