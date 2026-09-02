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
summary: "384 OF 396 TRANSLATION UNITS BECOME i386 OBJECTS, measured on a quiet tree at 0da8a0ae4 with binary 1652b00f68f1, and EVERY ONE OF THE 12 REFUSALS WAS ALREADY TICKETED: regex.h (7 TUs) and resolv.h (1), which want an IMPLEMENTATION rather than a header, and 4 inline-asm files that belong to the AT&T reader. **regex.h LANDED 2026-09-02 (2f920dfd4) and all 7 of its TUs now become i386 objects**, leaving resolv.h and the 4 asm files -- both ticketed. There is no unticketed blocker left in this ticket. First attempt, 2026-09-02, was 332 with 68 refusals -- 64 crtl HEADER gaps across 34 distinct headers, invisible on x86-64 where pxx falls back to the host's /usr/include and a cross target rightly cannot, plus the same 4 asm. All 34 landed, in five commits (eac7126f1, 037e38c64, 0baec7bad, c3e89bdee, and linux/fd.h), the last of which the sweep itself found: it was not in the 34-header table, because mkfs_vfat.c only became the next failure once the ones ahead of it were gone. The counts quoted mid-session (358, 367) were taken while headers were being edited under the sweep and are WITHDRAWN, not corrected -- a contaminated count is not a smaller true count. WHAT IS NOT YET MEASURED: the LINK. 384 objects is a compile result; the sweep refuses to link a partial set, correctly, so busybox-on-i386 as a running program is still gated on regex.h."
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

### 2026-09-02, evening — the clean sweep: 384 of 396, and nothing unticketed

Measured on a quiet tree, one binary, one commit, nothing edited underneath it
(`0da8a0ae4`, `1652b00f68f1`):

```
bb-sep: 396 translation units
bb-sep: objects ok=384 fail=12
```

| cause | TUs | where it lives |
| --- | --- | --- |
| `regex.h` | 7 | `feature-c-crtl-posix-regex-regcomp-regexec` |
| `resolv.h` | 1 | `feature-c-crtl-resolv-h-and-the-ns-parser` |
| inline asm (i386 template, `=&d` earlyclobber) | 4 | `feature-c-gnu-inline-asm-with-a-non-empty-template` |

**The sweep found a header the 34-header table did not have**, and that is the
method working rather than the table being wrong: `util-linux/mkfs_vfat.c` only
became the next failure once the ones ahead of it were gone. `linux/fd.h` is
now transcribed whole. It is the sharpest case in the crtl set for *whole, not
to taste*: `FDGETPRM` is `_IOR(2, 0x04, struct floppy_struct)`, so the struct's
SIZE is inside the request number — drop a field and the number changes, the
kernel does not recognise it, the ioctl fails, and mkfs_vfat uses that ioctl as
a **predicate** (success = "this is a real floppy"). A trimmed struct does not
give a wrong geometry; it takes the wrong branch and writes a boot sector
describing media it is not on.

**The LINK is still unmeasured and that is the honest state of this rung.** 384
objects is a compile result. The sweep refuses to link a partial object set —
correctly, since undefined references from twelve missing TUs say nothing — so
busybox-on-i386 as a *running* program is gated on `regex.h`, which is 7 of the
12 and the only one with real size to it.

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


## 2026-09-02, night — regex.h landed, and two ways to count the wrong thing

`2f920dfd4` gave crtl a POSIX regex engine. Re-measured individually, with the
flags busybox's own build uses, **all seven TUs that stopped at `regex.h` now
become i386 objects**: `libbb/xregcomp.c`, `editors/awk.c`, `editors/sed.c`,
`findutils/grep.c`, `coreutils/expr.c`, `coreutils/test.c`,
`util-linux/mdev.c`. That leaves `networking/nslookup.c` (resolv.h) and the
four `networking/tls_*` files (inline asm), both ticketed.

### Two instruments that answered instead of erroring

Neither produced an error. Both produced a NUMBER, and a plausible one.

**1. A hand-rolled sweep that omits `-include include/autoconf.h`.**
busybox's real build force-includes its config (`Makefile.flags`) and **no
busybox header includes it**. Without the flag ~2500 `IF_FEATURE_XXX(...)`
macros are undefined, so every invocation reaches the parser as an identifier
applied to a parenthesised expression. That produces, in three different files,
three different and entirely convincing C-frontend diagnostics:

    stray token at top level (not a declaration): 'IF_DESKTOP'
    expected ')' before 'IF_FEATURE_GREP_CONTEXT'
    undeclared identifier 'size_t' used as value (treated as 0)

A minimal repro of the same construct compiles correctly, which reads as
evidence the bug is CONTEXT-DEPENDENT rather than evidence the macro was never
defined. `-D_GNU_SOURCE` goes missing the same way and produces a bogus
`strncasecmp` refusal. `tools/busybox_diff.sh` gets this right -- it spells
autoconf.h into the wrapper preamble and asserts it is there. Nothing else does.

**2. Taking the TU population from `*.o` files on disk.**
Stale objects from a previous config survive a reconfigure, so a sweep over
them compiles files the current build does not. Four of the ten refusals found
that way -- `libbb/capability.c`, `shell/ash.c`, `networking/nslookup.c`, and
both `networking/udhcp/*.c` -- are `ENABLE_*=0` in the current config; **gcc
would refuse them too**, and `DEFINE_STRUCT_CAPS` is genuinely undefined when
`ENABLE_FEATURE_SETPRIV_CAPABILITIES` and `ENABLE_RUN_INIT` are both 0. The
population that means anything is `busybox_unstripped.map`, which is what
`busybox_diff.sh` reads.

### THE CONFIG IS SHARED MUTABLE STATE, AND A TU COUNT WITHOUT ONE IS NOT A CLAIM

`busybox_diff.sh --applets` rewrites `.config` and regenerates
`include/autoconf.h`. At 17:33 on 2026-09-02 a peer's run reconfigured the tree
underneath a sweep of mine, and as of this writing the link map holds **28**
TUs (the cat+echo scope), not the ~396 of the full-applet one. So `384/396`,
`424/438` and `28/28` are all true statements about different trees.

**Quote the applet scope and the map's TU count beside any number here**, the
way a binary sha is quoted beside a timing. A count on its own cannot be
checked, and the failure mode is not a wrong number -- it is a number that is
right about a build nobody else has.
