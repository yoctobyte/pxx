---
track: P
prio: 55
type: bug
blocked-by: []
summary: "`record case k: Integer of 0: (i: Integer) end` measured 12 bytes where FPC says 8: the variant part was always aligned to 8, charging the tag's own padding twice. Values were right (the branches do overlay) — the LAYOUT was not, so SizeOf, an array's stride, and any record shared with a file or a C library disagreed with FPC."
status: done
---

# A tagged variant record is padded to eight

- **Type:** bug (FPC layout divergence) — **Track P**, in the shared
  `compiler/parser.inc` (record layout), so it runs under Track A's gate.
- **Found:** 2026-08-16, by an FPC-differential sweep over Pascal dark corners.

## Measured (before)

| record | FPC 3.2.2 | pxx |
| --- | --- | --- |
| `case k: Integer of 0:(i: Integer); 1:(b: array[0..3] of Byte)` | 8 | **12** |
| `case k: Byte of 0:(i: Integer); 1:(c: Char)` | 8 | **12** |
| `case k: Integer of 0:(a: Int64); 1:(b: array[0..7] of Byte)` | 16 | 16 |
| `case Integer of ...` (no tag field) | 4 | 4 |

Every VALUE was right — the branches overlay correctly — so nothing computed a
wrong answer inside pxx. What differed is the layout: `SizeOf`, the stride of
an array of the record, and the bytes of any such record written to a file or
handed to a C library.

## Root cause

`ParseRecordVariantPart` began the variant part at
`AlignTo(curOff, TARGET_PTR_SIZE)` — always 8. FPC starts it at the alignment
the BRANCHES need. With a 4-byte tag and a 4-byte branch, that is 4, and the
extra 4 was the tag's own padding charged a second time.

## Fix

The branches' alignment is only known once they are parsed, and laying them out
from an under-aligned base would move them relative to each other. So: lay out
from the 8-aligned base (which satisfies every branch), track the maximum
branch alignment, and at the end shift every field this part created down by
`8-aligned base - AlignTo(tagEnd, maxBranchAlign)`. That delta is a multiple of
the branch alignment, so the relative offsets survive it.

Packed records are untouched (they already start right after the tag).

## Result

`test/test_variant_record_tag_padding.pas` — eight sizes (tagged/untagged,
byte/int/wide tags, a leading fixed field, packed, nested, and an array of the
record), plus the overlay reads that must keep working — prints
`total ok 14 / 14` under both FPC 3.2.2 and pxx.

Not fixed and not the same thing: a `string[N]` branch measures 24 where FPC
says 12, because pxx's frozen-string slot is its own representation
(`bug-a-a-frozen-string-field-in-a-variant-part-is-8-bytes-and-untyped` chose
it deliberately).

## Gate

`make compiler/pascal26` + the test under both compilers + `tools/gate.sh
quick` — GREEN.

## Log
- 2026-08-16 — resolved, commit PENDING-COMMIT.
