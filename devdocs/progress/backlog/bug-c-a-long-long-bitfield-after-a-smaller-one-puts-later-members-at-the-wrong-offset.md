---
track: C
prio: 50
type: bug
status: backlog
blocked-by: []
owner: ""
summary: "MEASURED 2026-08-30: not one shape -- 135 of 400 random bitfield structs lay out differently from gcc (34%), in BOTH directions (72 larger, 27 smaller), and 36 have an identical sizeof with different member offsets. Root cause is a MODEL difference (pxx storage-unit vs gcc bit-cursor), not a bad condition, and it is entangled with the bitfield ACCESS WIDTH -- so the fix spans cparser.inc + cir.inc (C) and IRLowerBitFieldRead's signature in ir.inc (A). Diagnosis banked, deliberately not microfixed. Values are always correct; blast radius is pxx/gcc interop only."
---

# A `long long` bitfield after a smaller-typed one puts later members at the wrong offset

- **Track C** — the C bitfield layout is computed in `compiler/cparser.inc`
  (the `bfBitBytes` / `UFldBitBytes` path, ~:12048-12823).
- **Found:** 2026-08-30 by frankC, measuring the bitfield-layout item that
  `feature-c-csmith-differential-fuzzing` has carried **unfiled since
  2026-07-13**. Its note said *"`sizeof` of a packed bitfield struct is 12 where
  gcc gives 8"*. That exact shape does not reproduce; a different and worse one
  does.
- **Do not confuse with `bugfix-cfront-bitfield-packing-gcc-compat`**, which is in
  `rejected/` — it was rejected as a *false diagnosis of the sqlite VdbeCursor
  crash*, having measured pxx and gcc as matching on that struct. Different
  subject; its rejection says nothing about this.

## The measurement — compiler `f2bfbb3c94a5` (self-host fixedpoint at HEAD)

```c
struct T { unsigned a:1; unsigned long long b:33; int tail; };
```

| | pxx | gcc |
| --- | ---: | ---: |
| `sizeof(struct T)` | 16 | 16 |
| `offsetof(struct T, tail)` | **12** | **8** |

**The sizes are identical and the member offset is not.** That is the serious
half: a struct-size assertion — the obvious thing to test, and what the July note
described — passes while a real member sits four bytes away from where every
other toolchain puts it.

Without the trailing member the size diverges too:

```c
struct S { unsigned a:1; unsigned long long b:33; };   /* pxx 16, gcc 8 */
struct S v[3];   /* pxx: stride 16, total 48   gcc: stride 8, total 24 */
```

## The boundary, mapped

| declaration | pxx | gcc | |
| --- | ---: | ---: | --- |
| `unsigned a:1; unsigned long long b:33;` | 16 | 8 | **DIFF** |
| `unsigned a:1; unsigned long long b:32;` | 16 | 8 | **DIFF** |
| `unsigned a:1; unsigned long long b:31;` | 16 | 8 | **DIFF** |
| `unsigned a:1; unsigned long long b:1;` | 16 | 8 | **DIFF** |
| `unsigned long long b:33;` alone | 8 | 8 | ok |
| `unsigned long long b:64;` | 8 | 8 | ok |
| `unsigned long long a:1,b:1,c:1,d:1;` | 8 | 8 | ok |
| `unsigned long long a:1; unsigned b:1;` | 8 | 8 | ok — **order matters** |
| `unsigned char a:1; unsigned b:1;` | 4 | 4 | ok |
| `unsigned short a:1; unsigned b:1;` | 4 | 4 | ok |
| `unsigned a:3; unsigned b:5; unsigned c:30;` | 8 | 8 | ok |
| `unsigned a:3; unsigned :0; unsigned b:3;` | 8 | 8 | ok |
| **`unsigned a:1; unsigned long long b:1; unsigned c:1;`** | **8** | **8** | **ok — a trailing field FIXES it** |

So it is not width-driven and not a general packing defect:

- It needs a **narrower declared type followed by `long long`**. The reverse
  order is fine. `char`/`short` before `unsigned` is fine.
- **A trailing `unsigned` field makes it correct again**, which says the defect is
  in how the unit is closed out, not in where `b` is placed.

## Why no fuzz batch will ever find this

**The values are always right.** Measured: `s.a=1; s.b=0x1FFFFFFF` reads back
`a=1 b=8589934591` under both compilers, and the 3-element array holds
`1000 1001 1002` in both.

csmith's oracle is a checksum of the globals. A layout that stores and loads
consistently produces an identical checksum at any size, so `MISCOMPILE_VS_GCC`
cannot fire. The July note said exactly this — *"values are right, so the
checksum oracle CANNOT see it; it breaks ABI/interop instead"* — and it is why
the item survived 443 clean comparisons on 2026-08-30 and would survive 443,000.

The harness has a `LAYOUT_SUSPECT` bucket, but it triggers on a *divergence in a
program containing bitfields*, and there is no divergence here to trigger it.

**This is the class of bug that only gets found by someone deliberately
comparing layout**, which is an argument for a `sizeof`/`offsetof` differential
against gcc as its own small tool — and note it must compare **offsets**, not
just sizes, or it reproduces the July note's blind spot.

## Why it matters despite the values being right

Inside a wholly pxx-compiled program the layout is self-consistent and nothing
misbehaves. The harm is at a boundary, and the boundaries are real for this
compiler:

- **Binary formats and wire protocols** — anything that maps a struct over bytes
  written by other software. This compiler builds zlib, sqlite and lua.
- **Data written by a gcc-built program and read by a pxx-built one**, or the
  reverse.
- **`offsetof` used for manual pointer arithmetic**, which gets a different answer
  than every other toolchain.

Object-file interop is **not** currently a route — x86-64 refuses `--emit-obj`
for general programs and aarch64 has no object writer at all — but
`feature-a-a-general-x86-64-relocatable-object-writer` would open it, and this
should be fixed before that lands rather than discovered through it.

## Gate

Track C's: `make compiler/pascal26` to fixedpoint + the table above matching gcc
row for row. A `test/` case belongs beside the existing `cbitfield_*` block and
must assert **`offsetof` of a following member**, not only `sizeof` — the July
note tested the size and that is why the sharper half went unrecorded for seven
weeks.

Re-run the eight `cbitfield_*` tests: this changes layout, so anything asserting
a current size will move, and each such change needs checking against gcc rather
than updating to match.


## SCALE AND ROOT CAUSE — frankC, 2026-08-30. Diagnosed, deliberately NOT fixed.

I built a layout differential (`sizeof` + `offsetof` of every named non-bitfield
member, pxx vs gcc) and pointed it at 400 randomly generated bitfield structs.

**135 of 400 diverge — 34%, with 0 errors.** This is not a corner case and the
title under-reports it: the `unsigned`-then-`long long` shape is one visible
instance of a systemic difference.

A first, ad-hoc corpus gave 95/400 (24%); the reproducible generator published
below gives **135/400** because it mixes in more anonymous `:0` breaks and plain
members between bitfields. **Cite the 135** — it is the one anyone can regenerate
(`genlayout.py 20260830 400`), measured at `239142c9b`, binary `83a767151ffa`,
`converged after 1 round(s)`.

Breakdown of the 135, and the last row is why this ticket needed a new instrument:

| | count |
| --- | ---: |
| pxx struct LARGER than gcc | 72 |
| pxx struct SMALLER than gcc | 27 |
| **identical `sizeof`, different member offsets** | **36** |

The 27-vs-72 split is the bidirectionality that kills the one-line fix. The 36
are the ones no size assertion can ever catch — a struct that measures right and
is laid out wrong.

### It is a MODEL difference, not a bad condition — and the divergence runs both ways

The tempting fix is `cparser.inc:12702`'s third clause:

```pascal
if (bitUnitOff < 0) or (bitUnitUsed + bitWidth > bitUnitSize * 8) or
   (sz > bitUnitSize) then            { start a fresh unit when the type widens }
```

**That clause is not the bug, and patching it would break rows that pass today.**
pxx is smaller than gcc as often as it is larger:

| shape | pxx | gcc |
| --- | ---: | ---: |
| `unsigned a:1; unsigned long long b:33;` | 16 | 8 |
| `unsigned a:2; unsigned long long b:63;` | 16 | **24** |
| `unsigned a:30; unsigned long long b:40;` | 16 | **24** |

A one-directional "widen the unit instead of starting a new one" makes the first
row right and the other two worse.

**The two compilers use different allocation models:**

- **pxx: a storage-unit model.** `bitUnitOff` / `bitUnitSize` / `bitUnitUsed` —
  a unit is opened at a declared-type width and fields are packed into it. A
  following member is placed after **the whole unit**.
- **gcc: a bit cursor with per-type alignment constraints.** Bits are allocated
  continuously; a field of declared type `T` is advanced only if it would cross a
  `T`-alignment boundary; and a following non-bitfield member goes at the next
  suitably-aligned byte **after the last used bit**, not after a reserved unit.

The clearest single piece of evidence is `unsigned long long a:1,b:1,c:1,d:1;
int tail;` — four bits used out of a 64-bit declared type:

```
gcc:  sizeof 8,  offsetof(tail) = 4      <- 4 bits used, tail at the next int boundary
pxx:  sizeof 16, offsetof(tail) = 8      <- the whole 8-byte unit is reserved first
```

No adjustment to *when a unit opens* produces gcc's answer there, because gcc
never reserved a unit to begin with.

### Why I am banking this rather than fixing it

Per `root-cause-over-microfix`: the honest fix is replacing the unit model with a
bit cursor, and that is a change to a **working ABI** with cited bug-fix history
in its own comments — `bug-c-long-long-bitfield-promotion` (the `:40` field read
through only its low 32 bits), quickjs's `JSString` header (`uint8_t wide:1`
after `uint32_t len:31`), c-testsuite 00218 (enum bitfield signedness). Those
were paid for, and a model swap re-opens all of them.

It is also the exact shape the playbook warns against finishing badly: a
one-clause change would turn some of the 95 green, leave others, silently move
rows that pass today, and close the ticket. **Microfix as a consolation is
explicitly the thing not to do here.**

What is needed before the model is replaced is the instrument, not more
opinion — see the harness handed to Track T below. With it the change becomes
measurable in one command instead of arguable.

### The instrument exists and is the deliverable of this pass

The differential is written up in
`feature-t-a-layout-oracle-dimension-the-checksum-is-blind-to-offsets` [T p40],
including the script, so it can be lifted rather than rebuilt. **Its baseline is
`pass=265 diff=135 error=0`** over `genlayout.py 20260830 400` at `239142c9b` —
the number any fix must move toward 400/0 without regressing the 265 that pass.

Note one property it must keep: it separates **ERROR** (a compiler could not
build the probe) from **DIFF** (both built and disagreed). My first version
conflated them and reported 20 spurious diffs, because `offsetof` on a bit-field
member is illegal C and gcc was failing to compile the probe at all — "could not
look" printing as "ruled out", inside the very tool built to catch that class.

### Prio raised 40 -> 50

24% of random bitfield structs, not one shape. Still layout-only — values are
always correct and no pure-pxx program misbehaves — so it stays below a
wrong-value bug, but it is far broader than the original filing implied.

## THE FIX REACHES OUTSIDE cparser.inc — layout is entangled with ACCESS WIDTH

This is the part that changes who owns the ticket, and I nearly missed it by
reading only the placement code. The reason pxx reserves a whole unit is not a
layout opinion — it is a **codegen constraint**, stated outright at
`cparser.inc`'s unit-advance:

```pascal
{ A long-long bitfield unit is LOADED/STORED as 8 bytes (IRBitStorageTk),
  so it occupies a full 8-byte unit -- reserve that much or the next field's
  unit overlaps it and an 8-byte store clobbers this one. }
if sz >= 8 then bitUnitBytes := 8 else bitUnitBytes := bitBytes;
```

So `unsigned long long a:1,b:1,c:1,d:1; int tail;` reserves 8 bytes for 4 bits
and puts `tail` at 8; gcc uses a narrower access and puts it at 4. **pxx cannot
simply adopt gcc's offset**: with the current lowering, an 8-byte store to the
unit at offset 0 would clobber a `tail` sitting at offset 4. The layout is
correct FOR THE ACCESS WIDTH IT USES.

That makes this a two-part change:

1. **Placement** (`cparser.inc`, Track C) — bit cursor instead of storage units.
2. **Access lowering** (`cir.inc`, Track C) — the load/store width must derive
   from the field's actual bit span, not its declared type.
3. **The seam** (`ir.inc`, **Track A**) — `IRLowerBitFieldRead` is forward-declared
   at `ir.inc:686` and called at `ir.inc:7040` and `ir.inc:10117`, taking
   `storageTk: TTypeKind` **from the caller**. A per-field byte span is not a
   `TTypeKind`, so that signature changes, and with it two Track A call sites.

**Reporting this per the coordinator's request: yes, the fix reaches outside**
**`cparser.inc`, into `ir.inc` (Track A).** Under the file-lane rules that is a
Track A ticket to be filed and handed off, not something to edit under C — and
it is a further reason this is not a session-sized microfix.

### Pinned rows — a model change must NOT move these

`test/cbitfield_mixed_type_pack_b373.c` (the quickjs `JSString` header) asserts
`sizeof == 24`. I re-checked it against gcc rather than trusting it:

```
gcc:  sizeof=24 len=123456 wide=1 hash=777 atype=2 next=9   exit=42
pxx:  sizeof=24 len=123456 wide=1 hash=777 atype=2 next=9   exit=42
```

Identical. That test was blessed correctly and is a pinned row, not a candidate
for updating-to-match. Same for the three sibling `cbitfield_*` tests (values,
not layout) and c-testsuite 00218's enum-bitfield signedness.

### One severity bound, measured

pxx packs differently but does **not** misalign: in `r36`
(`unsigned char b0:7; int b1:30; unsigned short :0; short p; int t`) pxx places
the plain `short` at offset 6 vs gcc's 8 — different, but still 2-aligned and
legal. Across the corpus I saw no case of a plain member landing at an offset
its own type could not tolerate. So the blast radius is **interop only**
(a struct crossing a pxx/gcc boundary), never a self-inconsistent pxx program.
