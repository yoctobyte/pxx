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
summary: "32 OF THE 34 HEADERS ARE IN, and the two that are left are the two that were never headers: regex.h (7 TUs) and resolv.h (1), both filed as their own tickets because they want an IMPLEMENTATION. First attempt, 2026-09-02: 332 of busybox's 400 translation units became i386 objects and three pxx i386 objects linked with `gcc -m32` and ran. Of the 68 refusals, 64 were crtl HEADER gaps across 34 distinct headers -- invisible on x86-64, where pxx falls back to the host's /usr/include and a cross target rightly cannot -- and 4 were inline asm, which is the AT&T reader's ticket, not this one. Landed since in four commits: eac7126f1 (15 headers), 037e38c64 (8 + statvfs over statfs), 0baec7bad (the rtnetlink family, 3.3k lines transcribed whole), and the SysV IPC family. A CLEAN RE-SWEEP IS OWED and the 332 above is the only number in this ticket that was measured: the counts quoted mid-session (358, 367) were taken while headers were being edited under the sweep and are withdrawn."
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

### 2026-09-02, later the same day — 32 of the 34 are in

Every header in the table above now exists under `lib/crtl/include/` except
**`regex.h`** and **`resolv.h`**, and those two were always the odd ones out:
they want an implementation, not a transcription, and each has its own ticket
(`feature-c-crtl-posix-regex-regcomp-regexec`,
`feature-c-crtl-resolv-h-and-the-ns-parser`). That is a filesystem fact, checked
by looking; **it is not a claim that the 64 TUs now compile** — the re-sweep
that would say so has not been run against a quiet tree yet, and the two
mid-session numbers that were quoted (358, then 367 of 396) were measured while
headers were being edited underneath the sweep. They are withdrawn rather than
corrected: a contaminated count is not a smaller true count.

One thing the header work turned up that is NOT a header: `semctl`'s fourth
argument. crtl's implementation reads the `union semun` slot the way glibc and
musl do, and pxx puts a POINTER to a caller temp there for any aggregate passed
through `...`. It is filed as
`bug-a-c-a-struct-through-the-variadic-tail-is-passed-as-a-pointer` and is not
worked around here. It does not block any TU from compiling, and the two
applets that would hit it at runtime (`ipcs`, `ipcrm`) are not in the harness's
applet list; `syslogd` and `logread`, which are, use only `semop` and
`semctl(IPC_RMID)` and are unaffected.

## The other 4

`networking/tls_pstm_mul_comba.c`, `tls_pstm_sqr_comba.c` and `tls_sp_c32.c`
stop at *"inline asm with a non-empty template is only supported on x86-64, not
i386"*, and `tls_pstm_montgomery_reduce.c` at *"earlyclobber constraint
\"=&d\" is not supported"*. Both are the AT&T reader
(`feature-c-gnu-inline-asm-with-a-non-empty-template`, done for x86-64) meeting
a target and a constraint it does not cover yet. Not this ticket.

## The harness

**Done, 2026-09-02.** `tools/busybox_diff.sh --separate` no longer names any
target: `sep_probe` asks the tools three independent questions per target —
can pxx emit an object for it, does a linker HERE link that object, does the
result run HERE — and each failure gets its own sentence. Measured on this box:
x86_64 `gcc`, i386 `gcc -m32`, riscv32 stops at the linker (it has a writer),
aarch64/arm32 stop at the writer, and **xtensa is named in the compiler's own
`supported:` list and stops at the compiler anyway**, on *"prologue slot
zero-init not implemented"* — which is precisely why the question is now asked
of the compiler instead of a list of target names. The comparison itself needs no change: every target is already compared
against the x86-64 gcc transcript, because busybox's observable behaviour in
these cases is not architecture-dependent.
