---
track: P
prio: 70
type: bug
found: 2026-09-02
found-by: frankB
owner: frankB
summary: "ONE OF THREE FIXED, and my original diagnosis of it was WRONG in both direction and severity. An `array[0..N] of string[M]` as a RECORD FIELD strode 264 bytes (LOCAL_STR_CAP+8) instead of 18 -- but NOT because layout dropped the capacity, which is what this ticket first said. Layout is correct: measured at the decl site, fTk=tyFixedString, fStrCap=10, fSize=18, and SizeOf agrees at 36. The INDEX path was wrong. A `string[N]` field is stored as tyString with its capacity in UFldStrCap, so the index path took its bare-string arm. And it is not a fat layout, it is MEMORY CORRUPTION: the field is 36 bytes inside a 40-byte record, so element 1 lands 224 bytes PAST THE RECORD and `r.inner[1] := s` clobbered five words of an unrelated local. The VALUE rows pass throughout -- write and read share the wrong stride and agree with each other outside the record -- so nothing but a stride or guard assertion can see it. Fixed by adding the record-FIELD base kind to ir.inc\'s index sizing, the third arm of a case whose array-symbol and `p^[i]` arms were already there. STILL OPEN, and confirmed still NOT the same cause: an open-array parameter (correct stride 18, a[2] still empty) and `array of array of string[10]` (element corrupted)."
status: working
---

# A `string[N]` element keeps its capacity in one container and loses it in three

## Measured

Same declaration in four containers, `pxx` at `d830b2c56`, oracle `fpc -O- -Mobjfpc` 3.2.2:

| shape | stride pxx | stride fpc | value |
| --- | ---: | ---: | --- |
| `var oa: array[0..2] of string[10]` | 18 | 11 | correct |
| `record inner: array[0..1] of string[10]` | **264** | 11 | correct here, but see below |
| `const a: array of string[10]` (open array) | 18 | 11 | **`a[2]` empty** |
| `array of array of string[10]` | — | — | **element corrupted** |

18 is right for pxx (`FrozenStrSlotSize` = cap+8); FPC's 11 is cap+1, which is
the separate representation question and NOT what this ticket is about. The
defect is 264, and the two wrong values.

**264 is `DEFAULT_STR_CAP + 8` padded** (255+8 = 263 -> 264). So the declared
`10` was not merely mis-sized, it was **dropped**, and the "no capacity
recorded" default substituted.

`SizeOf(nest.inner)` answers **36** — 2 x 18, correct for the declaration —
against a real stride of 264. One declaration, two sizing paths, disagreeing by
more than 7x. Same class as
[[bug-p-sizeof-answers-pointer-width-for-a-string-n-that-occupies-more]] with the
arms swapped: there SizeOf was wrong and layout right, here layout is wrong and
SizeOf right. That is the argument for the umbrella's one-oracle end condition
rather than a fix on either side.

## Not from the SizeOf work, and not one cause

All three reproduce on `stable_linux_amd64/default/pinned`, which predates the
2026-09-02 `SizeOfSlot` change. That change *improved* two rows here
(`SizeOf(cls.f)` 8 -> 18, `SizeOf(nest.inner)` 16 -> 36) and moved no stride.

**They are at least two causes, and the ticket should not be closed on one.**
The open-array parameter has the CORRECT stride of 18 and still reads `a[2]`
empty, so whatever loses the capacity in (1) is not what breaks (2). Verified
by measuring the stride from inside the callee.

## Lead for (1)

`ir.inc:11260` sizes a record array field's element with
`FrozenStrSlotSize(UFldTk[faFldIdx], UFldStrCap[faFldIdx])`, and `UFldStrCap`
holds **the field's own** capacity, not its element's. For
`inner: array[0..1] of string[10]` the field is an array, so its own capacity is
0, and `FrozenStrSlotSize` maps 0 to `DEFAULT_STR_CAP` — which is exactly 264.

This is a shape the codebase already knows about twice: `ArrTypeElemStrCap`
exists because `AliasStrCap` could not also hold the element's, and
`SymPtrElemStrCap` exists because `SymStrCap` could not — its `defs.inc` comment
says so and cites the bug where `p^[1]` read at the wrong offset. The record
field table is the third instance and has no `UFldElemStrCap`.

`pasparser_decl.inc` already threads a local `aElemStrCap` from
`ArrTypeElemStrCap` for a NAMED array element type, which suggests the named
spelling may behave differently from the inline one — worth measuring both
before fixing, since that is the double-case shape this repo keeps hitting.

## Gate

`make test` + self-host + cross. Strides are ABI. Assert the STRIDE directly and
in each of the four containers: a value-only test passes on every element that
fits inside the mis-sized slot, which is why a 7x layout error has been sitting
under a green suite. Include the plain-var row — it is the one that works, and a
fix that "corrects" it has over-reached.


## 2026-09-02 (frankB) — one fixed, and the diagnosis above it was wrong

**Correcting this ticket's own lead before anything else.** It said `UFldStrCap`
holds the field's own capacity where `ir.inc:11260` reads it as the element's,
and that layout dropped the declared 10. **Both halves are wrong**, and I found
that only by probing the compiler instead of reading it — the arithmetic could
not discriminate, because `DEFAULT_STR_CAP + 8 = 263` aligns to 264 and
`LOCAL_STR_CAP + 8` is 264 exactly, so two different causes produce the same
observed stride.

A temporary probe at the field-decl site printed, for `inner: array[0..1] of
string[10]`:

    fTk=26 (tyFixedString)  arrLen=2  fStrCap=10  LastTypeStrCap=10  fSize=18

The declaration path is **correct**, `SizeOf(r.inner)` is 36, and the record is
40 bytes. The defect was entirely in the **index** path.

## What it actually was

`ParseRecordFields` stores a `string[N]` field as `Ord(tyString)` with its
capacity in `UFldStrCap` — deliberately, because the read/write codegen is
identical and only the slot SIZE differs. So `RecFieldType` answers `tyString`,
and `ir.inc`'s index sizing took its bare-string arm, `LOCAL_STR_CAP + 8`.

That arm already had the same case handled for two other base kinds — an array
SYMBOL, and `p^[i]` through a pointer, whose comment describes this exact
264-byte stride for a 15-byte slot. The record FIELD base was the third arm,
never written. `normalise-dont-special-case`: the arm nobody wrote is the one
that stays broken.

## Severity was understated: this WRITES outside the record

The two sibling arms read outside an array. A record field's array is only
`ArrLen * slot` bytes **inside** the record, so:

    SizeOf(R)                          40
    stride                            264
    @inner[1] beyond the record's end  224 bytes
    guard words clobbered by `r.inner[1] := 'bbbbbbbbbb'`   5

Ordinary declared Pascal, silently corrupting a neighbouring local.

**And every value row passes while it happens.** The write and the read use the
same wrong stride, so they agree with each other 224 bytes outside the record
and `r.inner[1]` reads back exactly what was stored. Measured on the pinned
binary as the positive control: `stride 0  fits 0  guard 0  tail 1  values 11`.
A value-only test certifies the corruption as correct.

`test/test_string_n_array_field_stride.pas` asserts the field's stride against a
plain VAR of the same array type — the invariant, not 18 — so it survives the
byte-prefix feature. Holds on i386, aarch64, arm32 and riscv32.

## Still open, and still not one cause

Re-measured after the fix:

    openarr   stride 18 (correct) and a[2] still reads EMPTY
    dyn2d     `array of array of string[10]` element still corrupted

The open-array one having the right stride and the wrong value is the reason
this ticket said the three are not one cause. That prediction held. Do not close
this on the record-field fix.
