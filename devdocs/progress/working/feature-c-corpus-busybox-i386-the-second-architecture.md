---
slug: feature-c-corpus-busybox-i386-the-second-architecture
title: "Rung 5: busybox on i386 — the second architecture, and the 34 headers x86-64 was borrowing"
track: C
prio: 65
type: feature
status: working
created: 2026-09-02
found-by: frankD
owner: frankD
summary: "**i386 AT 394 APPLETS: 492 OF 521 TUs BECOME OBJECTS, 29 REFUSE -- and the refusal set is LARGER than x86-64's 14, for a reason that makes the x86-64 number unreliable rather than better.** The host-header fallback is NATIVE-ONLY: on x86-64 an unknown `<h>` resolves from /usr/include with a warning, on any cross target it is a hard `include file not found`. So 16 of the 29 are crtl headers x86-64 was silently borrowing from glibc (`bug-b-crtl-host-header-fallback-leaks-BEGIN-DECLS`, reframed and re-summarised on this evidence), 8 are the same declaration gaps x86-64 sees (`feature-b-crtl-function-gaps-at-394-busybox-applets`), and 5 are a genuine i386 compiler gap -- inline asm is x86-64-only (`bug-c-inline-asm-is-x86-64-only-so-five-busybox-tus-refuse-on-i386`). **THE NATIVE TARGET IS THE ONE WITH THE BLIND SPOT HERE**, which is the reverse of the usual asymmetry and is why this axis exists. Earlier figure on this ticket (265/265 at 141 applets) was a different, smaller scope and is not comparable; the scope is now a file, `tools/busybox-applets-394.txt`. Binary sha256 1968c7a7da57, commit 5f598d4a7."
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


## 2026-09-02, night — i386 LINKS AND RUNS; and the map is an exact set for ONE architecture

Full 140-applet scope, `--separate`, binary `cd239178b3a0`:

```
  ORACLE  gcc separate build, 265 objects (387 cases)
  ORACLE  busybox agrees with the gcc build
  PASS    x86_64   byte-identical to the gcc oracle over 387 cases
  note    i386     +libbb/bb_bswap_64.c (defines `bb_bswap_64` for this target)
  note    i386     266 objects linked separately with `gcc -m32` (167179260 bytes)
  FAIL    i386     differs from the gcc oracle          <- one case, ticketed
```

**x86-64 is the first green full-applet separate build.** It previously stopped
at `getnameinfo` in `libbb/xconnect.c`; the header work cleared it.

**i386 compiles completely** -- 265 of 265 -- and now links and runs. The single
differing case is `mv copy.txt moved.txt`, filed as
`bug-a-i386-a-pointer-is-register-and-memory-resident-at-once-across-a-goto-entered-loop`
with stat/lstat/S_ISDIR/errno already measured out as the cause.

### The link failure that was not a pxx bug

The first i386 attempt compiled all 265 objects and then failed to link on ONE
undefined symbol, `bb_bswap_64`. `include/platform.h`:

```c
#if ULONG_MAX > 0xffffffff
/* inline 64-bit bswap only on 64-bit arches */
# define bb_bswap_64(x) bswap_64(x)
#endif
```

with `libbb/bb_bswap_64.c` self-guarded by the exact complement,
`#if !(ULONG_MAX > 0xffffffff)`. On x86-64 the macro shadows the function, the
TU compiles to an object **that defines nothing**, the link never pulls it, and
it is therefore ABSENT FROM `busybox_unstripped.map` -- grep count zero. On i386
the macro does not exist and every `SWAP_BE64` becomes a real call.

**The TU list was derived from a map produced by a HOST x86-64 link.** Together
with the stale-`*.o` finding recorded above, that is a matched pair, and the
playbook now carries both (section 89, written up by frankC from this
measurement):

| population | shape | what it gets wrong for a cross target |
| --- | --- | --- |
| `*.o` on disk | a SUPERSET that never shrinks | members the current config does not compile |
| the link map | an EXACT SET, for the machine that produced it | MISSING what only the target needs |

**Name the architecture beside the map exactly as you name the config.**

### And the host archive cannot answer the question

The first resolver looked up which `lib.a` member defines the missing symbol
and found nothing -- and its negative control also found nothing, so it could
not tell "my `awk` is broken" from "no member defines it". A positive control
on `bb_cat` showed the `awk` was fine and that `libbb/bb_bswap_64.o` is a
genuinely EMPTY archive member: present, defining no symbols. The host has no
definition to point at. **Only the target build has one**, so the resolver has
to compile the candidate for the target and ask that object.

`tools/busybox_diff.sh` now does exactly that on a cross link failure: candidate
sources by text, restricted to the sources this config compiled (read off
`ar t` of the archives, so a stale `*.o` can never become a candidate), each
compiled for the target, and the one whose OBJECT defines the symbol is kept.
Every addition is printed with the symbol that caused it. Bounded at three
rounds, and a round that resolves nothing says so out loud rather than falling
through -- "the link failed and I found nothing to add" and "the link succeeded
first time" are the same silence in a log skim.

# 2026-09-04: the 394-applet measurement, and what it says about x86-64

Scope is `tools/busybox-applets-394.txt` (394 applets, 521 TUs). Binary sha256
`1968c7a7da57`, commit `5f598d4a7`, private tree via `PXX_BUSYBOX_DIR` with an
isolated `TMPDIR`. The oracle on that private tree gave **521 objects, 893
cases, agreeing with the reference busybox** -- byte-identical to what the
shared tree produced, so the private-tree route is proven equivalent rather
than assumed to be.

**29 refusals, in three groups:**

| n | group | ticket |
| --- | --- | --- |
| 16 | crtl header missing; masked on x86-64 by the native-only host fallback | `bug-b-crtl-host-header-fallback-leaks-BEGIN-DECLS` |
| 8 | crtl declaration missing; identical on both targets | `feature-b-crtl-function-gaps-at-394-busybox-applets` |
| 5 | inline asm is x86-64-only in the C frontend | `bug-c-inline-asm-is-x86-64-only-so-five-busybox-tus-refuse-on-i386` |

## The finding, and it inverts the prediction this ticket was opened on

I predicted the crtl gaps were width-independent and the two refusal sets would
therefore overlap almost completely. **The gaps are width-independent; the
MASKING is not.** `pascal26` searches `/usr/include` on a native build and not
on a cross build -- correctly, since host headers carry the host's ABI -- so
every missing crtl header is invisible on x86-64 for as long as glibc happens
to have a header of that name.

x86-64 was not passing those 16 TUs. It was compiling them **against glibc's
headers**, which the compiler says out loud as a warning nobody was reading:

```
warning: #include <sys/xattr.h> resolved from the host system (/usr/include),
         not pxx's own headers -- ABI/macro mismatches may silently misbehave
```

**So the x86-64 count of 507/521 is flattered and the i386 count of 492/521 is
the honest one.** Not "i386 is behind"; i386 is measuring something x86-64
cannot see. CLAUDE.md warns that width and alignment defects are structurally
invisible on the x86-64 host -- this is the same asymmetry with the sign
flipped, and the reason it bites harder is that here the native target is the
DEFAULT one.

## Two TUs have two blockers, and only the native one was visible

`miscutils/flash_eraseall.c` was root-caused on x86-64 as a missing `loff_t`
(correct, and fixed in `697e92745`). On i386 it never reaches that line -- it
stops at `linux/jffs2.h`. `networking/ether-wake.c` and `shell/hush.c` are the
same shape: x86-64 reported `ether_hostton` and `sigisemptyset`, i386 stops
earlier at `linux/if.h` and `glob.h`.

**"Fixed on x86-64" is therefore not "fixed", and a per-target row is what
closes an item at this scope.** The failure mode is not a wrong answer, it is a
ticket that closes green with a second blocker untouched behind it.

## The link, and what is NOT yet claimed

493 objects did not link -- every `*_main` belonging to a refused TU is an
undefined reference, plus `curve_P256_compute_pubkey_and_premaster` from the
refused tls TUs. **Nothing has RUN on i386 at this scope.** The 893 cases are
proved against the gcc oracle only. The one runtime divergence this axis has
ever produced is at 141 applets and is
`bug-a-i386-a-pointer-is-register-and-memory-resident-at-once-across-a-goto-entered-loop`.

The harness's cross-link resolver added `libbb/bb_bswap_64.c` again and said so
(`the host map was short 1 translation unit(s) for this target`) -- the
map-is-per-architecture behaviour this ticket already documents, working.


## The 16 headers were a LOWER BOUND, and the census could not have said so

Seven have landed: `linux/if.h`, `linux/if_arp.h`, `linux/if_vlan.h`,
`linux/jffs2.h`, `sys/vt.h`, and then `linux/if_bonding.h` and `linux/mii.h`.
**The last two are not additions to the list. They were never on it**, and the
reason is mechanical: a translation unit reports **one** missing include and
stops. `networking/ifenslave.c` could not ask for `linux/if_bonding.h` while
`linux/if.h` was still missing, and `ifplugd.c` could not ask for `linux/mii.h`.
Measured 2026-09-04 — the three `linux/if.h` users all advanced to a *different*
blocker the moment it landed:

```
FAIL i386 networking/ether-wake.c  error: call to undeclared function: ether_hostton
FAIL i386 networking/ifenslave.c   error: C include file not found: "linux/if_bonding.h"
FAIL i386 networking/ifplugd.c     error: C include file not found: "linux/mii.h"
```

So **a missing-header count taken from one run is a lower bound, never the
list**, and this ticket's own table of 34 has to be read that way. It is the
same shape as the two-blockers-per-TU section above, but recursive: the native
fallback masked every layer *simultaneously*, so peeling one reveals the next
rather than finishing it. The only honest completion signal is a run where
nothing refuses — not a table that has been fully worked through.

`ifenslave.c` and `ifplugd.c` both go on to want `linux/ethtool.h`, and
`ifplugd.c` `linux/wireless.h`; that surface is small (`ETHTOOL_GDRVINFO`,
`ETHTOOL_GLINK`, `struct ethtool_drvinfo`, `struct ethtool_value`, `struct
iwreq`) and is the next layer down, not the last one.

All seven are diffed against the host's own headers by
`test/c_crtl_uapi_headers_from_busybox_i386.c`, which is compiled for **i386**
in the same run precisely because that is the target where no host-header
fallback can make a wrong file look right. Positive control run 2026-09-04:
shadowing `BOND_ABI_VERSION` to 3 via `-I` makes the comparison report the
row — the guard fires.

**A first cut of `linux/if_vlan.h` also carried `VLAN_HLEN`, `VLAN_ETH_ALEN`,
`VLAN_N_VID` and `struct vlan_hdr`.** Those are kernel-*internal*, in no
user-facing header, so there was no oracle for them and the values would have
been mine rather than measured. gcc refusing the probe is what caught it. A
constant nobody can diff is a liability in a shadow tree, not a convenience.
