---
slug: decide-a-what-a-set-costs-bits-bytes-bounds-and-what-file-of-t-writes-to-disk
title: "Set representation: bits vs bytes, whether width follows declared bounds, and what `file of T` writes"
track: U
prio: 40
type: decide
status: backlog
created: 2026-09-02
found-by: owner (raised 2026-09-02), measured by frankuser
owner: ""
summary: "OWNER RAISED THE FORK: a byte-per-element set may save instructions over a bitset, against compactness winning for file IO and low-memory targets like ESP. FIRST, A PREMISE CORRECTION THAT CHANGES THE QUESTION: we are ALREADY bitpacked. 32 bytes is a fixed 256-BIT width, one bit per ordinal over 0..255 — not a byte per element (defs.inc:2003 `{ 21: Set — 32-byte bitset }`; IR_SET_LIT bakes a 32-byte MASK). The four-type-sizes ticket's `sets are not bitpacked` was false and is corrected. So the live fork is NOT bits-vs-bytes for storage; it is (a) whether the WIDTH follows the declared bounds, and (b) what a set looks like ON DISK once `file of T` exists, because that is where a representation stops being an implementation choice. RECOMMENDATION: keep bits, narrow the width, and decide the on-disk form SEPARATELY from the in-memory one. Bytes lose on set algebra by 8x and the one case they could win — single-element membership on a target with no bit-test instruction — is already compiled away, because `c in ['a'..'z']` against a LITERAL lowers to comparisons and never builds a set at all."
---

# What a set costs, and what goes on disk

## The premise the fork was raised on, corrected first

The owner's consideration was *"a set of bytes is possibly faster / might save
some instructions compared to a set of bits — for file IO the most compact
version would win, or for low memory targets like esp."*

That trade is real in general, but **we are already on the bit side**, and the
ticket that prompted it said otherwise. Measured 2026-09-02:

- `SizeOf(set of 0..7)` = **32**, membership value correct (own run).
- `defs.inc:2003` — `tySet, { 21: Set — 32-byte bitset }`
- `defs.inc:614`, `:3282` — `IR_SET_LIT` lowers to a *"baked 32-byte **mask**"*.

32 bytes × 8 = **256 bits, one per ordinal 0..255** — which is exactly the
owner's own read of it: *"makes sense because a set is up to 256 entries."* A
byte-per-element set of the same range would be 256 bytes, not 32.

So the defect in the split ticket is **width that ignores the declared bounds**,
not packing. That matters for cost: a packing change is a lowering change; a
width change is an **ABI** change (by-value class, `IR_SET_COPY`'s contract,
every backend). Opposite conclusions about how big the job is.

## Why bytes lose even where they look attractive

**Set algebra is 8:1 against bytes.** Union/intersection/difference over 32
bytes is 4 × 64-bit ops. The same range byte-per-element is 256 bytes — 32 ×
64-bit ops. Every `+`, `*`, `-` on sets pays that.

**The membership case bytes would win is already gone.** On a target with no
bit-test instruction (xtensa, riscv32, arm32) `x in s` costs shift+mask+test
where a byte array costs load+compare — a genuine few instructions. But the hot
form in real Pascal is `c in ['a'..'z']`, a **literal**, and that never builds a
set: it lowers to comparisons directly (`ir_codegen_wasm32.inc:2322`,
`WasmEmitSetIn`). The representation only bites for set *variables*, where
algebra dominates.

**NOT MEASURED, and I am not claiming it:** the actual x86-64 instruction
sequence for membership on a set *variable*. objdump would not parse our binary
and `PXXDBG=a.ir:main` did not fire on the program body. If someone wants to
argue the byte side on instruction count, that is the measurement to take, on
xtensa rather than x86-64, and it should be taken before this decide is closed.

## The three questions

**1. Does the in-memory width follow the declared bounds?**
Recommend **yes**. This is the split ticket
[[bug-a-a-set-is-32-bytes-whatever-its-bounds-and-the-ir-opcode-says-so]], and
ESP is the strongest argument for it — the owner named low-memory targets, and
`set of 0..7` at 4 bytes instead of 32 is precisely that win. Cost is an ABI
change, which is why it is ranked as a codegen slice.

**2. Do we copy FPC's rule, or do better?**
FPC: 4 bytes when the high bound ≤ 31, else 32, **and it does not rebase to
`lo`** — so `set of 200..207` is 32 in FPC, where rebasing would give 1. We
could beat FPC there. **Open**, and it is a real fork: beating FPC on layout is
free in memory and costs us layout compat, which only matters once (3) exists.

**3. What does `file of T` write?**
**This is the one that must not be decided by accident.** `file of T` makes
layout an on-disk value — the reason the four-type-sizes ticket was ever
ranked. Recommend **deciding the on-disk form separately from the in-memory
one**: a file format that inherits whatever the current in-memory width happens
to be means (1) and (2) silently change what old files mean. The compact form
the owner wants for file IO and the fast form for registers do not have to be
the same form, and coupling them is the mistake that is cheap to avoid now and
expensive later.

## The owner's proposal, and the two forks inside it

Owner, 2026-09-02: *"we keep internal structure at 32 byte, always. and we
offset and truncate on file output and the reverse on input."*

**Agreed on the shape** — decouple, and derive the disk form from the DECLARED
TYPE so the format is a function of the source rather than of codegen. That is
the cheap version of question (3) and it is strictly safer than narrowing
memory: no ABI change, no `IR_SET_COPY` contract change, none of the 115
`tySet` sites move.

**Fork A — it drops the ESP win the owner himself raised.** `set of 0..7` still
costs 32 bytes of RAM on xtensa, and an array or record of them still costs 8x.
Disk gets compact; memory does not. Question (1) is the only thing that buys
the low-memory target, and this proposal declines it. That may well be the
right call — it is the expensive half — but it should be declined knowingly,
not absorbed.

### FPC's actual rule, measured first-hand (fpc 3.2.2, `-O-`, 2026-09-02)

The owner questioned the no-rebase claim — *"a set of ['x'..'z'] would take more
than 1 byte on fpc since they start counting at zero?"* — and he was right to.
Measured rather than repeated, because two unmeasured FPC numbers already got
into these tickets today:

```
set of 0..7        4
set of 0..31       4
set of 0..32      32
set of 32..63     32     <- spans exactly 32 values, still 32 bytes
set of 200..207   32
set of 'x'..'z'   32     <- three bits wanted; 'z' is ordinal 122
set of Char       32
```

**The width is a function of the HIGH BOUND ALONE**: 4 if `hi <= 31`, else 32.
There is no rebasing and no span term — `set of 32..63` needs one word's worth
of bits and gets 32 bytes, because bit 63 must exist at index 63.

**This makes the owner's offset idea a real improvement over FPC, not merely a
compaction of our own waste.** `set of 'x'..'z'` would be 1 byte against FPC's
32. That is what makes Fork B a genuine choice rather than a formality.

**Fork B — offsetting and FPC-readable files are mutually exclusive.** FPC
truncates (small-set word, high bound ≤ 31 → 4 bytes) but **does not rebase to
`lo`** (frankb-a9, measured), so `set of 200..207` is 32 bytes in an FPC file.
Rebasing gives us 1 byte and a file FPC cannot read. `feature-pascal-typed-and-
untyped-files` names a **byte-for-byte comparison against FPC's written file**
as its acceptance test, so the two cannot both hold. **This is NOT the
FPC-parity nitpicking the 2026-09-02 rules retired**: a file is an outward
artifact another program reads, so the format is a contract rather than an
intermediate, and matching it buys real interop. Recommend **truncate, do not
offset** unless the owner would rather have the smaller file.

## Consequence that lands under EVERY option

**If any type's on-disk form differs from its in-memory form, `file of T` is a
field-by-field MARSHALLER, not a blit.** Decide it now — the feature is not
built, so this is the cheap moment. It is more RTL work, and it changes what
`BlockRead`/`BlockWrite` mean over a typed handle.

It also creates a documented trap: `SizeOf(s)` answers **32** while `Write(f,s)`
puts 1 or 4 bytes on disk, so `BlockWrite(f, s, SizeOf(s))` writes 32 and
desynchronises the file. Under the 2026-09-02 `SizeOf` rule that 32 is a
TRUE statement about our representation and not a defect — but the gap between
it and the on-disk width is a hazard the RTL docs must name.

## Not blocking

The split ticket can proceed on (1) without this decide closing — narrowing the
in-memory width is right under every option here. Only (3) must land before
`file of T` writes a set to disk.
