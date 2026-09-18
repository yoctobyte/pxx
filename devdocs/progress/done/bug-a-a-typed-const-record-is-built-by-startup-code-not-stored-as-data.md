---
track: A
prio: 35
type: bug
blocked-by: []
summary: "FIXED 2026-09-18 (frankH): a typed const RECORD, and an array of records, whose every field init is a plain ordinal literal is now initialised .data (TryBakeConstRecordIntoData) -- 100 extra 16-byte records went from +11,600 code/+1,600 bss to +6 code/+1,600 data/+0 bss. Byte-identical to the startup-store image on a 22-shape corpus on x86-64, i386, aarch64, arm32, riscv32 and xtensa. Fails CLOSED and still refuses: string/set/pointer-valued inits, FLOAT fields (the record parser does not record them as kind 3 -- unexplored, safe), array fields, FIdx paths (no field-array low bound recorded), subrange and bit fields. Writable .data ({$J+}), never read-only. Null row: SysUtils/Classes/DateUtils/StrUtils/Math bake nothing, so the win is in user code, not the RTL."
status: done
owner: "frankH"
---

# A typed const record is built by startup code, not stored as data

- **Type:** bug (codegen / const lowering) — **Track A**.
- **Filed:** 2026-08-28 by the wasm32 lane (branch `wasm`), from the data-segment
  slice `test/wasm/data_slice.pas`, where a typed const record read back as zero
  under wasm while every typed const *array* in the same program read correctly.
- **Sibling of** [[bug-a-a-typed-const-array-is-built-by-startup-code-not-stored-as-data]]
  (done, prio 40). That ticket fixed arrays of scalars. This is the case it did
  not reach, and it is the case its own closing note asks about: *"if you fix a
  bug on one arm of a double case, grep for the sibling before closing the
  ticket"* (`devdocs/dev/normalise-dont-special-case.md`).

## The bug

A typed constant whose type is a record — or an array **of** records, or a
record containing one — does not become initialised data. It becomes a BSS
reservation plus generated code, one store per field, run at program start. The
data path exists and works: an array of scalars of the same total size lands in
`.data` at zero code cost.

## Measurement

Two programs each, differing only in element count. `pxx <src> <out>` prints the
sizes.

**Records — `array[0..N-1] of TP` where `TP` is four `Integer`s (16 bytes):**

| N | code | data | bss |
| --- | --- | --- | --- |
| 1 | 61,854 | 1,960 | 42,468 |
| 101 | 73,454 | 1,960 | 44,068 |
| **delta (100 records, 1,600 bytes)** | **+11,600** | **unchanged** | **+1,600** |

**116 bytes of code per record; 29 bytes per Integer field** — the same
per-element figure the original ticket measured for `Cardinal`.

**The scalar array of the same storage, for contrast — `array[0..N-1] of Integer`:**

| N | code | data | bss |
| --- | --- | --- | --- |
| 1 | 61,768 | 1,968 | 42,452 |
| 400 | 61,768 | 3,560 | 42,452 |
| **delta (399 elements, 1,596 bytes)** | **unchanged** | **+1,592** | **unchanged** |

Zero code, all data. That is what the record case should do.

A bare record const (`R1: TP = (A: 11; B: 22)`, no array) does it too, and so
does a nested one (`NEST: TN = (P: (A: 7; B: 8); C: 9)`) — a three-const program
emits **ten** separate top-level initialiser chunks.

## Repro

```pascal
program TC;
type
  TP = record A, B: Integer; end;
  TN = record P: TP; C: Integer; end;
const
  R1:     TP = (A: 11; B: 22);
  ARR:    array[0..1] of TP = ((A: 1; B: 2), (A: 3; B: 4));
  NEST:   TN = (P: (A: 7; B: 8); C: 9);
  SIMPLE: array[0..2] of Integer = (5, 6, 7);   { this one IS data }
begin
  writeln(R1.A, ' ', ARR[1].B, ' ', NEST.P.B, ' ', SIMPLE[2]);
end.
```

Correct natively (`11 4 8 7`). Compile it with `--target=wasm32` to a `.wat` path
: `R1`, `ARR` and `NEST` appear as `i32.store` sequences in
top-level chunks, while `SIMPLE`'s bytes are in the data segment.

## Why the wasm lane cares, and why that does not change the track

On every shipping target this is a **size and startup-time** cost, not a wrong
answer — the startup code runs and the constants are correct. The wasm32 lane
hit it as a wrong answer only because that target had no startup path at the
time, which is the lane's own gap and is now fixed on its branch (`main` is
synthesised from the chunks). So this stays what the sibling was: a codegen
efficiency bug in Track A, ranked on the bytes, not a correctness escalation.

It is worth recording *how* it was found, because the mechanism generalises: a
target with no automatic startup makes "initialised by generated code" and
"initialised data" observably different, where on a normal target they are
indistinguishable from inside the language. That is the same reason wasm32 was
the first consumer to notice `IRTk` is not reliably populated
(`devdocs/dev/ir-as-substrate.md`) — a new backend is a new oracle for
assumptions six existing ones could not see.

## Gate

Per `CLAUDE.md`: `make compiler/pascal26` (which IS the byte-identical self-host
fixedpoint) plus the repro above. Sizes before and after for both tables in the
measurement section.

## Resolution (frankH, 2026-09-18)

`TryBakeConstRecordIntoData` (symtab.inc), called from the record-const site
and, after the scalar baker declines, from the array-of-records site. Each
pending init's target PATH (element index, first field span, deeper PIPath
spans) is resolved through `FindUField`/`UFldOff_` (the table the AN_FIELD
lowering reads) to a byte offset and a width, and the literal is written there
in init order, into a zeroed image the size of the BSS slot it replaces.
Everything is resolved before anything is written. A refusal half-way would
otherwise leave bytes past DataLen, and DataEnsure does not re-zero those.

**Measured:** the ticket's `array[0..N-1] of TP` table, N=1 -> 101:
code +6 (was +11,600), data +1,600 (the records' own bytes), bss +0 (was +1,600).
The repro prints `11 4 8 7` with all three record consts baked.

**Verified as an image, not as values.** A 22-row corpus dumps every const's
raw bytes. Covered shapes: mixed widths, enums, nested records three deep,
variant arms, packed, negative low bounds, partial initialisers, and {$J+}
writes after baking. It is byte-identical between this compiler and HEAD's
(which builds the same image with startup stores) on x86-64, i386, aarch64,
arm32 and riscv32, with both binaries asserted to exist and to print. xtensa
compares against x86-64 instead, because HEAD's xtensa binary faults (below).

**Guard:** `test/test_const_record_in_data.pas`, two rows in test-core. Row 2
reads `PXXDBG=a.constdata` and asserts exactly which consts were baked
(`cOuter cVar cEn cPart aNeg`), with the string-field and float-field records
refused. Values alone cannot fail, and HEAD bakes 0 of them.

**Found on the way, pre-existing, not this change** (tickets filed):
xtensa gives variant arms DIFFERENT start offsets (`A@8 L@4`; x86-64 8/8,
i386 4/4), and any unaligned packed-record field access faults on xtensa
(`r.I` at offset 1 -> SIGBUS, HEAD and this build alike).

## Log
- 2026-09-18 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
