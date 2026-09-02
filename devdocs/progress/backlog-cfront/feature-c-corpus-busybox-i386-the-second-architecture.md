---
slug: feature-c-corpus-busybox-i386-the-second-architecture
title: "Rung 5: busybox on i386 — the second architecture, and the 34 headers x86-64 was borrowing"
track: C
prio: 65
type: feature
status: open
created: 2026-09-02
found-by: frankD
owner: frankD
summary: "First attempt, 2026-09-02: 332 of busybox's 400 translation units already become i386 objects, and three pxx i386 objects link with `gcc -m32` and run. The 68 failures have exactly two causes and neither is about i386 codegen. 64 are crtl HEADER gaps -- 34 distinct headers, led by regex.h (7 TUs), netinet/udp.h (7), linux/fs.h (6), sched.h (5) -- that the x86-64 build never had to face because pxx falls back to the host's /usr/include there and a cross target rightly cannot. 4 are inline asm: the AT&T reader is x86-64 only and one arm needs an earlyclobber constraint. This ticket is the header set; the asm is its own."
---

# The second architecture, and what the first one was borrowing

`--emit-obj` has had an i386 object writer for days (`TargetHasObjectWriter`
names x86-64, i386, xtensa and riscv32). `tools/busybox_diff.sh --separate`
still refuses every target but x86-64 with *"--emit-obj has no object writer for
this target"* — a sentence that is false for two of the four and is the third
time this same fact has gone stale in a message (see `TargetHasObjectWriter`'s
own comment, which records the previous two).

Measured before writing any of this down. All 400 wrapper TUs from the GREEN
x86-64 run, recompiled with `--emit-obj --target=i386`:

**332 objects, 68 refusals.** And separately, three pxx `--emit-obj
--target=i386` objects link with `gcc -m32` into a binary that runs and prints
the right answer — so the link and run halves are not the obstacle either.

## What the x86-64 GREEN was standing on

**64 of the 68 are crtl header gaps, and they are invisible on x86-64 because
the host fallback covers them.** That build emits **1053** `resolved from the
host system (/usr/include), not pxx's own headers` warnings over **110**
distinct headers. So rung 4's claim is exactly *"pxx compiles and links busybox
and its output is byte-identical to gcc's"* — it is **not** *"crtl is enough to
build busybox"*, and the second sentence is the one a reader supplies for
themselves. A cross target has no fallback to borrow, which is why i386 is the
instrument that says so and x86-64 never could.

The 34 headers, by how many translation units each one stops:

| header | TUs |
| --- | --- |
| `regex.h` | 7 |
| `netinet/udp.h` | 7 |
| `linux/fs.h` | 6 |
| `sched.h` | 5 |
| `netinet/ether.h` | 4 |
| `linux/types.h` | 3 |
| `sys/prctl.h` | 2 |
| `linux/vt.h` | 2 |
| `linux/netlink.h` | 2 |
| `arpa/telnet.h` | 2 |
| `sys/vfs.h` | 1 |
| `sys/uio.h` | 1 |
| `sys/timex.h` | 1 |
| `sys/swap.h` | 1 |
| `sys/statvfs.h` | 1 |
| `sys/personality.h` | 1 |
| `sys/mtio.h` | 1 |
| `sys/klog.h` | 1 |
| `sys/kd.h` | 1 |
| `sys/ipc.h` | 1 |
| `sys/file.h` | 1 |
| `resolv.h` | 1 |
| `netinet/if_ether.h` | 1 |
| `mtd/mtd-user.h` | 1 |
| `linux/version.h` | 1 |
| `linux/sockios.h` | 1 |
| `linux/input.h` | 1 |
| `linux/if_tun.h` | 1 |
| `linux/i2c.h` | 1 |
| `linux/hdreg.h` | 1 |
| `linux/capability.h` | 1 |
| `features.h` | 1 |
| `asm/unistd.h` | 1 |
| `asm/types.h` | 1 |

`regex.h` is not like the others: it wants an implementation, not a header, and
it should be its own ticket the moment anyone starts it. Most of the rest are
structs, ioctl numbers and constants.

## The other 4

`networking/tls_pstm_mul_comba.c`, `tls_pstm_sqr_comba.c` and `tls_sp_c32.c`
stop at *"inline asm with a non-empty template is only supported on x86-64, not
i386"*, and `tls_pstm_montgomery_reduce.c` at *"earlyclobber constraint
\"=&d\" is not supported"*. Both are the AT&T reader
(`feature-c-gnu-inline-asm-with-a-non-empty-template`, done for x86-64) meeting
a target and a constraint it does not cover yet. Not this ticket.

## The harness

`tools/busybox_diff.sh --separate` needs the per-target linker (`gcc` for
x86-64, `gcc -m32` for i386) and a refusal that distinguishes *no object
writer* from *no linker or runner on this host* — riscv32 has a writer and no
linker here, and one message for both reasons is how the first sentence went
stale. The comparison itself needs no change: every target is already compared
against the x86-64 gcc transcript, because busybox's observable behaviour in
these cases is not architecture-dependent.
