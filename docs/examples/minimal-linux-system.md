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
| `/opt/pxx/compiler` | `pascal26`, its builtin units, the RTL and `asmcore` sources |

Nothing else. No window system, no init system, no package manager, no libc.
`/init` mounts `/proc`, `/sys` and `/dev` and execs the shell.

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
| initramfs (compressed) | 9,292,142 |
| GRUB and ISO padding | 13,202,066 |

The BusyBox binary is 31 MB of the uncompressed payload, and **that is a known
defect rather than a cost of the approach.** BusyBox's own GCC build of the same
19 applets is 117 KB. The difference is that PXX currently emits each object with
a private copy of its runtime in a single `.text` section, so the linker cannot
discard the 85 redundant copies — the 86 objects' `.text` sums to within 824
bytes of the linked binary's. The fix is per-function sections, which lets
`ld --gc-sections` drop them; `--function-sections` already does the
relocation half of that work. Expect the binary to fall to well under a megabyte
when that lands.

## Known limits

- The applet set is the one the differential was measured on, so there is no
  `test` or `[` builtin (use `case` for conditionals) and no `poweroff` — shut
  down with `echo o > /proc/sysrq-trigger`. Line editing is off, so there is no
  command history at the prompt.
- **The system contains its compiler but cannot yet reproduce itself.** It can
  compile and run Pascal, and `tools/mkkiosk.sh --selfhost` shows the compiler
  rebuilding itself inside the guest to a byte-identical second stage. It cannot
  rebuild its own BusyBox, because PXX cannot consume an object file and the
  image carries no assembler or linker.
- `/dev/console` is the serial port, which is what a headless `qemu -nographic`
  or `-cdrom` run wants. In a graphical VM window you will see kernel messages
  but the shell will be on the serial line.
