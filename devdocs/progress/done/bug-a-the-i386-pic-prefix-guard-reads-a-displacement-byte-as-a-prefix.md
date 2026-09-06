---
track: A
prio: 45
type: bug
status: done
owner: ""
created: 2026-09-06
found-by: frankA
tags: [emit-obj, elf, i386, pic]
blocked-by: []
summary: "RESOLVED (see the commit recorded below). `I386PrefixBefore` decided whether a legacy prefix precedes an instruction by reading the byte before it, and cannot tell a prefix from the last byte of the PREVIOUS instruction. Measured: `Halt(code)` in PXXIoCheck compiles to `mov -0x10(%ebp),%eax` / `mov [glob],%eax`, and the `f0` of the displacement `-0x10` read as LOCK -- so the PC-relative rewrite was refused and the object kept ONE absolute .text relocation, which is what test-emit-obj asserts must be zero. THE COUNT WAS DATA-DEPENDENT AND THE ROW FLAPPED: one extra unrelated local in PXXIoCheck moved `code` off -0x10 and the count went 1 -> 0, so `done/bug-a-an-i386-object-carries-text-relocations-as-soon-as-it-uses-sysutils`\'s \'62 -> 0\' was TRUE WHEN MEASURED and was not a stable property. FIXED BY INVERTING THE FAILURE DIRECTION, not by the announce-every-prefix design this ticket first proposed and parked as needing an exhaustive audit: X386InstrStart records where the instruction BEGAN, the guard exits early only when the position matches, and a site that never sets it leaves a smaller offset and therefore REFUSES exactly as before -- so completeness is coverage, not soundness, and adoption is incremental. Adopted by the moffs family (A0/A1/A2/A3) through EmitMovGlobAcc, 42 sites; the prefixed 66 A3 store is deliberately not in it. Now 0, and 0 on the perturbed tree too, so the flap is gone as well as the count. test-emit-obj remains red for an OLDER reason this one was hiding: the xtensa link shim provides no ESP-IDF, 25 undefined references from the pin and from HEAD alike."
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

## RESOLVED — the guard now asks the call site instead of the buffer

Fixed the same evening it was filed, and the park reason above is superseded
rather than wrong: the repair it argued against (announce every PREFIX) really
does need the exhaustive audit, because a missed announcement flips the guard to
ACCEPT and that is the silent wrong-width access. **The repair that landed
inverts the failure direction, which is what makes it affordable.**

`X386InstrStart` records where the instruction being emitted BEGAN.
`I386PrefixBefore(pos)` exits early only when `pos` matches it. A site that
never sets it leaves an earlier, SMALLER offset — code offsets only grow — so
`pos` does not match, the byte test runs, and that site refuses exactly as it
does today. **Completeness is a coverage property, not a soundness one.**
Adoption is incremental and a miss costs position-independence, not correctness.

Adopted by the moffs accumulator family through `EmitMovGlobAcc`: A0/A1/A2/A3,
one opcode byte then the moffs, 42 sites. The 16-bit `66 A3` store is not in the
family and is deliberately not routed there — it has a prefix, and in
`EmitObjMode` it never reaches the sniffer at all because `EmitMovGlobAx16`
emits its whole PIC form itself. `xtensaenc.inc`'s `$A0`/`$A1` are xtensa
opcodes and are untouched. Cleared where `CodeLen` rewinds.

### Measured — and the row that matters is the flap, not the count

| `lib/rtl/textfile.pas` | old compiler | new compiler |
| --- | --- | --- |
| unmodified | 1 | **0** |
| one extra local in `PXXIoCheck` | 0 | **0** |
| restored | 1 | **0** |

The count no longer moves with an axis that has nothing to do with
position-independence. A before/after pair on the unmodified row alone would
not have shown that — it would have looked like any other fix, and this row
could reach 0 on its own.

PC32 floor 3147 on the same object, so "zero absolute" is not passing on an
object where nothing was emitted.

### What is still red on `test-emit-obj`, and it is older than this

`make test-emit-obj` now runs past the i386 relocation assertion and every other
i386 row, and stops later at the xtensa link — a failure this one was hiding.
`test/test_emit_obj.pas` pulls in the PAL socket/timer backend and the recipe's
shim provides no ESP-IDF, so the link wants `lwip_*`, `esp_timer_get_time` and
`vTaskDelay`. **25 undefined references from the PINNED compiler and 25 from
HEAD, on both xtensa ABIs; riscv32 links clean.** Filed as
[[bug-a-the-emit-obj-xtensa-link-shim-does-not-provide-the-pal-backends-esp-idf-symbols]].

Verified: `make compiler/pascal26` converged, `189e9b74036e`. `gate.sh quick`'s
only FAIL was a silent-assertion lint on `Makefile:15977` from `fecdfe6dc`,
which is not this change and is fixed alongside; `self-host fixedpoint` and
`testmgr --tier quick` both PASS.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 8a9f2ad2e.
