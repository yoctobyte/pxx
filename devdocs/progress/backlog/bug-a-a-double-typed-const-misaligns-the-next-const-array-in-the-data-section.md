---
slug: bug-a-a-double-typed-const-misaligns-the-next-const-array-in-the-data-section
track: A
prio: 55
type: bug
blocked-by: []
status: backlog
summary: "A scalar `Double` typed const leaves the data-section cursor on an ODD byte, so the next typed-const ARRAY is emitted unaligned. Measured: on xtensa the array lands at addr mod 8 = 3 -- not even 4-aligned -- and indexing it SIGBUSes. Not a float bug: the victim array can be `array of Int64` and it still faults; an `Int64` scalar in the same position does NOT trigger it. arm32 has the same defect one notch milder (mod 8 = 4) and gets away with it; x86-64, i386, aarch64 and riscv32 are correct."
owner: unassigned
---

# A `Double` typed const misaligns the next typed-const array

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
