---
summary: "`string[N]` is a word-prefix tyFixedString, so any record holding one is a different SIZE and LAYOUT than FPC's: `record s: string[10] end` is 24 bytes where FPC says 11. Values are all right; the bytes are not."
type: compat
prio: 25
track: P
---

# A `string[N]` field makes a record a different size than FPC's

- **Type:** compat (FPC layout parity) — Track P, in the shared
  `compiler/parser.inc` / `symtab.inc`, so it runs under Track A's gate.
- **Status:** backlog. **Not a new discovery so much as the missing measurement
  for a known interim**: `ParseTypeKind` already says so in a comment —
  "`shortstring` maps to a 255-cap tyFixedString (word-prefix layout, so sizing
  matches the reused frozen codegen). The true byte-length-prefix tyShortString
  (FPC ABI) is a later codegen slice." This ticket is that slice, with numbers.
- **Found:** 2026-08-16, Pascal oracle sweep vs `fpc -O- -Mobjfpc` (records
  topic). Sibling of [[bug-p-a-tagged-variant-record-is-padded-to-eight]],
  found the same way and fixed the same day — same class, different field kind.

## Measured

Only records containing a `string[N]` diverge. Everything else in the sweep
agrees — plain fields, `packed`, char arrays, pointer+byte, three integers:

| record | FPC 3.2.2 | pxx |
| --- | --- | --- |
| `record s: string[10] end` | 11 | **24** |
| `record s: string[10]; i: integer end` | 16 | **24** |
| `record s: string[3]; b: byte end` | 5 | **16** |
| `record s1, s2: string[10] end` | 22 | **48** |
| `record c: char; i: integer end` | 8 | 8 |
| `record b: byte; d: double end` | 16 | 16 |
| `packed record c: char; i: integer end` | 5 | 5 |
| `record a: array[0..2] of char; i: integer end` | 8 | 8 |
| `record p: pointer; b: byte end` | 16 | 16 |

The arithmetic: `FrozenStrSlotSize` gives `tyFixedString` a **8-byte NativeInt
length word** plus the capacity (`10 + 8 = 18`, aligned to 24), where FPC's
shortstring is **1 length byte** plus the capacity (`10 + 1 = 11`, alignment 1).
`tyShortString` — which computes `cap + 1` — already exists in
`FrozenStrSlotSize` and is simply not what `string[N]` resolves to.

Every VALUE is right: assignment, `Length`, comparison and `Copy` on such a
field all match FPC. What differs is the bytes — `SizeOf`, the stride of an
array of the record, and therefore any record written to a file, memcmp'd, or
handed to a C library.

## Why it is not just a constant to change

`tyFixedString` is the *reused frozen tyString codegen* — the word prefix is
what lets that path be shared. Switching `string[N]` to `tyShortString` means a
codegen slice: every load/store/Length/compare/concat site that assumes the
8-byte prefix needs the 1-byte form, on all six backends. That is the work the
existing comment defers, not an oversight to patch in one line.

Worth checking first whether the two can coexist by capacity — FPC's shortstring
caps at 255 by definition, so `string[N<=255]` could take the byte-prefix path
while the 8-byte form stays for pxx's own uncapped frozen strings — which is
probably why both kinds are in `FrozenStrSlotSize` already.

## Gate

The table above as a test with FPC's column as `.expected`; `gate.sh quick`;
self-host fixedpoint; cross targets, since the layout is ABI.
