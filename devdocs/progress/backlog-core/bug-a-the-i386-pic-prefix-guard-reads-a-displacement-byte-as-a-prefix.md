---
track: A
prio: 45
type: bug
status: backlog
owner: ""
created: 2026-09-06
found-by: frankA
tags: [emit-obj, elf, i386, pic]
blocked-by: []
summary: "`I386PrefixBefore` decides whether a legacy prefix precedes an instruction by reading the byte before it, and cannot tell a prefix from the last byte of the PREVIOUS instruction. Measured: `Halt(code)` in PXXIoCheck compiles to `mov -0x10(%ebp),%eax` / `mov [glob],%eax`, and the `f0` of the displacement `-0x10` reads as LOCK -- so the PC-relative rewrite is refused and the object keeps ONE absolute .text relocation, which is what `test-emit-obj` asserts must be zero. THE COUNT IS DATA-DEPENDENT AND THE ROW FLAPS: adding one unrelated local to PXXIoCheck moves `code` off -0x10 and the count goes 1 -> 0; removing it goes back to 1. So `done/bug-a-an-i386-object-carries-text-relocations-as-soon-as-it-uses-sysutils`'s '62 -> 0' was TRUE WHEN MEASURED and is not a stable property -- any lib/rtl change that shifts a frame offset onto a prefix byte value re-reds this row. The guard is deliberately conservative (its own comment says a backward scan cannot be made sound, and a false ACCEPTANCE is a silent wrong-width access) so the fix is to stop scanning: announce the prefix from the call site, the pattern this same file already uses for X386AddrImmPic."
---

# The i386 PIC prefix guard reads a displacement byte as a prefix

Measured 2026-09-06 at compiler `a4b3cd42d8da`, built at `5e6d6d829`. Reproduces on pin v405 too, so
it is not a regression — it is a property that surfaces and hides with unrelated
code motion.

## The instruction

`test-emit-obj` builds `test/c_obj_data_pascal.pas` for i386 and asserts zero
absolute `.text` relocations. It gets one:

    00028f26  00000301 R_386_32   .bss

In `PXXIoCheck` (`lib/rtl/textfile.pas`), which ends `Halt(code)`:

    28f22:  8b 45 f0        mov  -0x10(%ebp),%eax
    28f25:  a3 b8 92 00 00  mov  %eax,0x92b8        <- R_386_32, absolute
    28f2a:  e8 ...          call __pxx_run_finalizers

`emit.inc`'s `TryI386PcRelStore` handles `A3` explicitly — the moffs case is the
first arm in the function. It refuses because of its guard:

    if ((modrm = $A2) or (modrm = $A3)) and not I386PrefixBefore(CodeLen-1) then

`I386PrefixBefore` reads the single byte before the opcode and answers True for
`$66 $67 $F0 $F2 $F3` and the segment overrides. The byte before `a3` is the
`f0` of `-0x10` — the displacement of the preceding instruction. It is read as
LOCK, and the rewrite is refused.

## The count is data-dependent, and that is the part that matters

Perturbing an unrelated declaration moves the answer, so the answer came from a
channel and not from the program:

| `lib/rtl/textfile.pas` | absolute `.text` relocs |
| --- | --- |
| unmodified | **1** |
| one extra local added to `PXXIoCheck` | **0** |
| restored | **1** |

One local moves `code` off `-0x10`, its displacement byte stops being `f0`, the
guard stops false-refusing. **Nothing about position-independence changed.**

So `done/bug-a-an-i386-object-carries-text-relocations-as-soon-as-it-uses-sysutils`
is not wrong about what it measured — 62 really did become 0 at `cd4af7824` —
but "0" is not a property of the fix. It is a property of the frame offsets that
happened to exist that day. 46 commits touched `lib/rtl` since, and one of them
put a local at `-0x10` in a routine that stores to a global. **Any future
lib/rtl change can re-red this row, and the diff that does it will look
unrelated.** That is why this is filed rather than left as a flaky row.

## Why the guard is right to refuse and still has to change

Its own comment is the best statement of the trade-off and should not be
overridden lightly:

> It REFUSES rather than re-emitting the prefix in the right place, because
> scanning backwards for a prefix cannot be made sound: the preceding byte may
> be the last byte of the previous instruction and merely LOOK like one. False
> refusals cost position-independence on a handful of 16-bit accesses; a false
> acceptance costs a wrong-width memory access, which is silent.

Both halves are correct. The prediction — that false refusals would cost
position-independence — is exactly what happened; only the estimate of *how
often* was low, because it assumed the trigger was a real `66` prefix on 16-bit
accesses rather than any byte in the set appearing as data.

**Do not fix this by narrowing the prefix set** (e.g. "LOCK cannot legally
precede `A3`"). It is true and it does not help: `66` is both a legal prefix
here and a perfectly ordinary displacement or immediate byte, so the ambiguity
survives any narrowing.

## The fix shape

**Stop scanning; have the emitter say so.** `emit.inc` already uses exactly this
pattern for the address-as-immediate family — its comment reads *"announced by
the call site rather than sniffed off the end of the buffer — see
X386AddrImmPic."* The same treatment here: a variable recording the offset at
which a prefix was last emitted, set where prefixes are emitted, and
`I386PrefixBefore(pos)` becomes an exact comparison instead of a guess.

**Not attempted here, deliberately.** The change is only sound if *every* prefix
emission that can precede a rewritable i386 instruction sets it, and a missed
one converts a conservative refusal into the silent wrong-width access the guard
exists to prevent. `EmitB($66)` alone appears 88 times across seven files, not
all of them i386 instruction streams. Enumerating that set is the work, and
"I found them all" is precisely the claim that needs a positive control rather
than a grep — a probe that a missed site FAILS on, not just a count.

## Repro

    ./compiler/pascal26 -Fulib/rtl --emit-obj --target=i386 \
        test/c_obj_data_pascal.pas /tmp/pcr.o
    readelf -rW /tmp/pcr.o | awk '/Relocation section/{s=($0 ~ /rel\.text/)} \
        s && /R_386_32/{n++} END{print n+0}'      # want 0, gets 1

Note `awk` and not `strtonum`: this box runs mawk, where `strtonum` is undefined
and a scan written with it fails rather than answering — the Makefile row beside
this one records the same trap.
