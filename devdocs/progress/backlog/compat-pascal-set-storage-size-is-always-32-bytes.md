---
track: P
prio: 22
type: compat
blocked-by: []
summary: "Every set type is 32 bytes, whatever its element range: SizeOf(set of TE8) is 32 where FPC says 4, and a record holding one is 48 bytes where FPC lays out 12. Values are all correct — a layout divergence like compat-pascal-subrange-storage-size, and it costs 8x memory on small sets as well as breaking binary interop."
status: backlog
owner: unassigned
---

# A set is always 32 bytes

- **Track P** (Pascal frontend: set representation), tag **compat-pascal**.
- Found 2026-08-20 by an FPC differential probe over enums with explicit
  ordinals, sets and case labels — the probe was otherwise clean, which is worth
  saying: membership, `Include`/`Exclude`, `+ - *`, `=`, `<=`, `for..in` and
  `case` over an enum with holes all agree with FPC exactly. Only the SIZE
  differs.

## What differs

| type | FPC | pxx |
| --- | --- | --- |
| `set of TE8` (8 members) | 4 | 32 |
| `set of TE9` (9 members) | 4 | 32 |
| `set of TGap` (values 3..9) | 4 | 32 |
| `set of 0..7` | 4 | 32 |
| `set of 0..31` | 4 | 32 |
| `set of Boolean` | 4 | 32 |
| `set of Byte` | 32 | 32 |
| `set of Char` | 32 | 32 |
| `record a: Byte; s: set of TE8; b: Byte; end` | 12 | 48 |
| the same record `packed` | 6 | 34 |

FPC sizes a set by its element range with a 4-byte floor; pxx allocates a full
256-bit set for every set type. The two agree exactly where the range really is
0..255.

## Why it is not a bug

Nothing computes a wrong value — this is the same shape as
`compat-pascal-subrange-storage-size` (that one filed the same day, from the
same probe family). It costs 8x memory on small sets, and it breaks binary
interop: a record with a set written by pxx cannot be read by an FPC-built
program, and `BlockRead` of an FPC-written struct into a pxx record will not
line up.

## Why it is not cheap

The 32-byte set is baked into the set codegen — `IR_SET_BINOP` allocates 32
bytes of BSS per operation, and the membership/inclusion paths all assume a
256-bit map. Sizing sets by range means a width parameter through every one of
those, plus the record layout and the const-set literal emitter. It is a
representation change, not a table row, which is why this is filed rather than
fixed.

## When to do it

If a binary-interop or memory ticket makes it pay for itself — the two natural
triggers are typed-file I/O against FPC-written data
(`feature-pascal-typed-and-untyped-files`) and any embedded target where 32
bytes per set matters. Do it together with
`compat-pascal-subrange-storage-size`: they are the same job (storage size from
the declared range) over two type constructors, and doing one alone leaves half
the layouts still divergent.
