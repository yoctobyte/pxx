---
prio: 45
track: A
type: bug
status: backlog
summary: "Under -dPXX_SHORTSTRING, `record case k: Byte of 0: (s: string[4]); 1: (n: Integer) end` measures 12 bytes where FPC 3.2.2 says 8. Measured 2026-09-03: 16 before the frozen-field size fix and 12 after, so the field SIZE is now right and the remaining divergence is in how the variant part is based and padded. Values are correct; this is a LAYOUT claim, so it matters for a record read from a file, passed to C, or sized by a foreign compiler."
---

# A variant record with a shortstring branch is four bytes larger than FPC

```pascal
type TS4 = string[4];
     TRV = record case k: Byte of 0: (s: TS4); 1: (n: Integer); end;
```

| | SizeOf(TRV) |
| --- | --- |
| pxx, default mode | 24 |
| pxx, `-dPXX_SHORTSTRING`, before the frozen-field size fix | 16 |
| pxx, `-dPXX_SHORTSTRING`, after it | **12** |
| FPC 3.2.2 | **8** |

FPC's 8 is a 1-byte tag, the branch at offset 1 (a shortstring aligns to 1),
`max(5, 4)` bytes of branch, rounded to the record's 4-byte alignment.

The FIELD half is already fixed: a `string[4]` branch field is now sized
`cap + 1` and aligned 1 rather than taking a pointer width. What remains is the
variant part's BASE: `ParseVariantPart` lays the branches out from
`AlignTo(curOff, TARGET_PTR_SIZE)` and shifts back by the branch alignment
afterwards, which is the mechanism
[[bug-p-a-tagged-variant-record-is-padded-to-eight]] describes. Read that one
first -- this may be the same defect measured through a shortstring rather than
a second one, and if so it should be closed as a duplicate rather than fixed
twice.

Values are correct in every mode (`v.s := 'qrst'` reads back), so nothing
observable inside a pxx-only program is wrong.

DEFAULT MODE IS NOT A DIVERGENCE TO FIX HERE: 24 is the pxx-only 8-byte-prefix
layout, which phase 4 deletes. Only the flag mode has an FPC answer to match.

[[feature-p-implement-the-real-tyshortstring-byte-prefix-layout]]
