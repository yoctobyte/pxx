---
slug: bug-a-a-double-typed-const-misaligns-the-next-const-array-in-the-data-section
track: A
prio: 55
type: bug
blocked-by: []
status: backlog
summary: "TYPED-CONST ARRAYS ARE NOT ALIGNED AT ALL, on any target -- widened 2026-08-30 from the original filing below. A `Double` before the array is not the trigger: with NOTHING before it the array is already at mod 8 = 1 on x86-64. Measured 31 of 50 cells misaligned over 10 preceding shapes x 5 targets, residues 0/1/2/4/5/6; the same 50 cells with a `var` array are aligned every time, which is the control that localises it to the typed-const data path. The original per-target table is not reproducible by construction (the offset is a function of everything emitted earlier) and a fix must not be validated against it. Only xtensa faults; the rest is hardware tolerance, not correctness. xtensa unverified here."
owner: unassigned
---

# A `Double` typed const misaligns the next typed-const array

> **WIDENED 2026-08-30 — read the boundary measurement at the bottom first.**
> The title and the two tables below describe a `Double`-triggered defect on two
> backends. Measured, it is neither: typed-const arrays get no alignment on any
> target, and a `Double` is one of many things that can leave the cursor odd.
> The original filing is kept intact — its diagnosis of *shared* data-section
> accounting was right, and its numbers are a faithful record of what one
> program did on one binary.

## Repro — five lines

```pascal
program c5;
const Pi: Double = 3.14159;
      A: array[0..3] of Int64 = (1,2,3,4);
begin
  writeln('Pi @ ', PtrUInt(@Pi) mod 8, ' A @ ', PtrUInt(@A[0]) mod 8);
end.
```

| target | `Pi @` | `A @` | effect |
| --- | --- | --- | --- |
| x86-64 (oracle) | 0 | 0 | correct |
| i386 | 0 | 0 | correct |
| aarch64 | 0 | 0 | correct |
| riscv32 | 0 | 0 | correct |
| **arm32** | 0 | **4** | under-aligned; survives because two `ldr`s only need 4 |
| **xtensa** | 0 | **3** | **not even 4-aligned — SIGBUS on any index** |

Measured by printing the addresses from the program itself, not inferred from
the emitter. `Pi` is always fine; it is the array *after* it that moves.

## The boundary, bisected

Each of these is one edit away from the one before it:

| shape | result |
| --- | --- |
| `const Coef: array of Double` alone | **ok** |
| `const K: Integer` then the array | **ok** |
| `const K: Int64` then the array | **ok** |
| **`const Pi: Double`** then the array | **SIGBUS** |
| `const Pi: Double` then `array of Int64` | **SIGBUS** |
| `const Pi: Double` then a **`var`** array | **ok** |
| array first, `Pi` second | **SIGBUS** |

So the trigger is *a scalar `Double` typed const anywhere in the same const
section as a typed-const array*, and the victim's element type is irrelevant —
`array of Int64` faults identically. Order does not matter, which rules out a
simple "the previous item advanced the cursor by the wrong amount" reading of
just one direction and points at how the Double's storage is accounted for.

`var`-initialised arrays are unaffected, so this is the **const/data** path only.

## Why this is not Track F

Rank the mechanism, never the datatype. A `Double` is the *trigger*; the
*subject* is a data-section cursor that ends on an odd byte, and the observable
is a **crash**, not a wrong digit. The clinching evidence is that the program
that dies contains no float arithmetic at all — it sums an `array of Int64`.
CLAUDE.md: *"A crash, a hang, a wrong signature, a control-flow or codegen bug
that merely lives in float code — all stay ordinary bugs in their own lane at
their own prio,"* and *"when it is a close call it is NOT F."*

## Grep the sibling — and it pays

arm32 shows `A @ 4`: the same under-alignment, one notch less severe, and
**silent**, because arm32 loads an 8-byte value as two 4-byte loads and never
faults. Four backends are correct and two are wrong in the same direction by
different amounts, which is the shape of a bug in the SHARED data-section
alignment accounting rather than in either backend's arm. Fixing it in
`ir_codegen_xtensa.inc` would leave arm32 quietly emitting under-aligned
constant arrays.

Related but distinct: `599000083 fix(A): an array frame slot is pointer-aligned`
fixed the same category for **frame** slots. This is the data section.

## Provenance

Found by [[feature-s-the-xtensa-row-of-the-posix-syscall-table]]:
`test_cross_float_const` could not compile for xtensa until the syscall table
existed, and diverged from the oracle the moment it could —
`pi=3.14159 scale=2.00` then a bus error, with `coef=8.25` never printed.

---

## Boundary measured, 2026-08-30 (frankB — probes only, no fix)

Dispatched to test one thing: *does arm32 really mis-align in the same
conditions, and is there a case with every property of the failing set that
comes out aligned.* The answer to the first is yes — **and so does every other
target, including the one this ticket names as the oracle.** The defect is
larger than the ticket describes and its trigger is not a `Double`.

All measurements at pin **v393** (`1d69760deabe`), addresses printed by the
program itself.

### `Double` is not the trigger — nothing is

With **nothing at all** before it, the typed-const array is already misaligned:

```
program t;
const A: array[0..3] of Int64 = (1,2,3,4);
begin writeln(PtrUInt(@A[0]) mod 8); end.      -> 1 on x86-64, 4 on i386, 4 on arm32
```

Ten preceding shapes × five targets, `const array mod 8` / `var array mod 8`:

```
preceding const            x86-64  i386   arm32  riscv32 aarch64
(nothing)                  1/0    4/0    4/0    0/0    0/0
Double                     4/0    6/0    4/0    0/0    4/0
Int64                      6/0    1/0    0/0    0/0    4/0
Integer                    5/0    6/0    0/0    0/0    4/0
Byte                       5/0    6/0    0/0    0/0    4/0
Char                       5/0    6/0    0/0    0/0    4/0
AnsiString                 0/0    1/0    4/0    4/0    4/0
Double + Double            1/0    0/0    4/0    0/0    0/0
Single                     5/0    2/0    0/0    0/0    4/0
array of Byte x3           1/0    4/0    4/0    0/0    0/0
```

**31 of 50 cells misaligned. Observed residues: 0, 1, 2, 4, 5, 6.** Per target:
x86-64 9, i386 9, aarch64 7, arm32 5, riscv32 1. A `Double` before the array is
one row of ten and not the worst one.

### The control, and it is a clean one

**`var V: array[0..3] of Int64` is `mod 8 = 0` in all 50 cells.** Same element
type, same size, same program, same ten shapes, same five targets — and it is
aligned every single time. The only difference is typed-const versus `var`.

That is the case with every property of the failing set that does not fail, and
it localises the defect precisely: the `var`/BSS path aligns, the typed-const
data path does not align at all.

A second, weaker control worth keeping: `Int64 before` on arm32 gives 0. It is
**aligned by arithmetic, not by correctness** — the preceding bytes happened to
land right. Any row that reads 0 in the grid above is that kind of zero, which
is why the grid must not be read as "these cells are fine".

### Consequences for this ticket as written

- **The per-target table is not reproducible, by construction.** On this
  ticket's exact five-line program at v393 I measure i386 4, riscv32 4,
  aarch64 4 and **arm32 0** — three targets the ticket calls correct are
  misaligned, and the one it calls broken is not. Nothing changed except the
  compiler binary. The offset is a function of everything emitted before the
  array, so any change to the compiler or RTL shifts every number in the table.
  **A fix must not be validated against those numbers.**
- **The "boundary, bisected" table is measuring luck.** `Int64 then array -> ok`
  and `Integer then array -> ok` are cells that happened to land on 0; with
  nothing at all in front, the array is still misaligned. There is no shape
  that makes it right, only shapes that make it lucky.
- **The conclusion is right and understated.** The ticket says this is shared
  data-section accounting rather than a backend arm, and that a xtensa-only fix
  would leave arm32 silently under-aligned. Correct — and it is not two
  backends, it is all six. The others differ only in what their hardware
  tolerates: x86 permits any alignment, arm32 splits an 8-byte load into two
  4-byte loads, xtensa faults. **`sum of an array of Int64` returned the right
  answer at `mod 8` = 2, 4, 5 and 6 on every runnable target.** Silence here is
  hardware tolerance, not correctness.
- **Not Track F stands, and more firmly than the ticket argues.** Rank the
  mechanism: the mechanism has nothing to do with floats at all. The array is
  misaligned with no `Double` in the program.

### What a fix must assert

- The typed-const array is 8-aligned in **all 50 cells** of the grid above, not
  in the ticket's original program.
- `var` stays 0 everywhere (it is correct today; a fix that aligns const by
  routing everything through a new path must not disturb it).
- Alignment holds with **nothing** preceding the array — the case that shows
  there is no alignment step rather than a wrong one.
- Element types wider than the target word (`Int64`, `Double`) *and* an array
  whose element is a record, since the required alignment comes from the
  element type.

### Not measured, and left visibly absent

**xtensa.** It does not build here — `target xtensa: external (dynamic) …` from
the plain `writeln` probe, i.e. it needs the ESP platform flags this lane is not
set up for. Every xtensa claim in this ticket remains frankS's measurement,
uncorroborated by me. The `mod 8 = 3` figure in particular is the only observed
residue that is not even 4-aligned, and nothing in my grid reproduces an odd
residue on any other target — so it may be a distinct additional effect on that
backend rather than the same one worse. Untested either way.
