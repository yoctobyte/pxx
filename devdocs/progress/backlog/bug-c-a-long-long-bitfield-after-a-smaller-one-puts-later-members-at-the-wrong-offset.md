---
track: C
prio: 40
type: bug
status: backlog
blocked-by: []
owner: ""
summary: "`unsigned a:1; unsigned long long b:33;` starts a second allocation unit where gcc packs one: sizeof 16 vs 8. Worse, with a following member the SIZES MATCH (16 both) while offsetof differs (12 vs 8) -- a real member at the wrong offset, invisible to any sizeof check. Values are always correct, so the csmith checksum oracle is structurally blind to it."
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
