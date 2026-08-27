---
summary: "set (32 vs 4), subrange (4 vs 1) and string[N] (8 vs 21) all store wider or narrower than FPC; every VALUE agrees, only SizeOf and record layout differ -- one layout family, four filed measurements"
type: bug
track: P
prio: 25
---

# Four type sizes disagree with FPC — and every value agrees

**Umbrella, opened 2026-08-26.** Four tickets from the same 2026-08-16/20 FPC
differential probes. Each was filed separately; each says the same sentence in
its own words: *the values are all correct, only the storage size is wrong.*

## The measurements, together

| type | FPC 3.2.2 | pxx |
| --- | ---: | ---: |
| `set of TE8` ... `set of 0..31` (every set) | 4 | **32** |
| `SizeOf(TSmall)` where `TSmall = 10..20` | 1 | **4** |
| `SizeOf(TNeg)` where `TNeg = -5..5` | 1 | **4** |
| `SizeOf(packed record a: TSmall; b: TNeg; c: 0..255)` | 3 | **12** |
| `SizeOf(array[0..3] of TSmall)` | 4 | **16** |
| `SizeOf(ss)` where `ss: string[20]` | 21 | **8** |
| ~~`Ord(ss[0])` (shortstring length byte)~~ | 5 | ~~**0**~~ **fixed** |
| a `string[N]` field's contribution to a record's size | N+1 | 8 |

**One row is now closed.** `Ord(ss[0])` was fixed 2026-08-27 by
[[bug-p-index-0-of-a-frozen-string-is-not-the-length-byte]], and it is worth
saying how, because it bears on the rest of this ticket: index 0 was given its
own origin so it addresses the length word's LOW byte, rather than the storage
being changed to a real byte-prefix. So the *observable* is FPC's while the
*layout* is still pxx's — reads, writes, `inc(s[0])`, `var` parameters and
record fields all match FPC 3.2.2 byte for byte, and `SizeOf(ss)` still says 8.
That is deliberate: it makes the length byte usable today without paying the ABI
churn this ticket is about, and it does not foreclose the real fix. When the
byte-prefix lands, that origin becomes redundant and should be deleted, not
kept alongside — two mechanisms for one index.

Sets and subranges are **wider** than FPC; `string[N]` is **narrower**, because
it is a 255-cap `tyFixedString` (word-prefix) rather than a true
byte-length-prefix `tyShortString`. `ParseTypeKind` already says so in a comment
and calls the real thing "a later codegen slice". This is that slice, plus the
two sizing families that travel with it.

## Why these are one ticket

They are one question -- *what is a type's in-memory footprint* -- answered in
three places that each round up to a convenient machine word. Fixing one changes
record layout, packed-record layout, array stride and `SizeOf` for that type
alone, so doing them separately means paying the layout-churn and
re-measurement cost three times and living with a half-converted ABI in between.

## Why they are NOT closed under the FPC-parity ceiling

`CLAUDE.md` says we do not chase 100% FPC parity, and routes "our output
formatting differs" and unreachable observables to `rejected/`. **These are
neither.** A size is reachable by any compiling program: `SizeOf` feeds `GetMem`
and `Move`, record layout is what binary file I/O and every C-interop struct
sees, and `Ord(ss[0])` is the documented way to read a shortstring's length.
A program that writes a record to a file and reads it back with FPC gets
garbage. That is the "real Pascal source runs wrong" row of the table, not the
cosmetic one.

Ranked low (22-25) because little real code depends on it *yet* -- the corpus
rungs are what will raise it. Whoever brings up a rung that does binary I/O or C
structs should expect to meet this first.

## Gate

`make compiler/pascal26` + every row above diffed against fpc 3.2.2, **plus** a
record round-trip through a file written by one compiler and read by the other +
`tools/gate.sh quick`. Sizes are exactly the kind of change where the suite goes
green and the ABI moves under it, so cross-target sizes must be re-measured too.

---

# The folded tickets, verbatim

Each section below is a ticket that was filed separately and is now
part of this one. Nothing is summarised away: the repro tables, the
measured oracle output and the located source lines are the reason
these are worth keeping, and they are reproduced unchanged.

## A set is always 32 bytes

*(was `compat-pascal-set-storage-size-is-always-32-bytes`, prio 22)*

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

## A subrange type is always 4 bytes

*(was `compat-pascal-subrange-storage-size`, prio 22)*

# A subrange type is always 4 bytes

- **Track P** (Pascal frontend: subrange type sizing), tag **compat-pascal**.
- Found 2026-08-20 by an FPC differential probe over enums, sets and subranges.

## What differs

```pascal
type
  TSmall = 10..20;
  TNeg   = -5..5;
  TBig   = 0..70000;
  TR = packed record a: TSmall; b: TNeg; c: 0..255; end;
  TA = array[0..3] of TSmall;
```

| | FPC 3.2.2 | pxx |
| --- | --- | --- |
| `SizeOf(TSmall)` | 1 | **4** |
| `SizeOf(TNeg)` | 1 | **4** |
| `SizeOf(TBig)` | 4 | 4 |
| `SizeOf(TR)` (packed) | 3 | **12** |
| `SizeOf(TA)` | 4 | **16** |

Every *value* agrees — `r.a`, `r.b`, `a[0]`, `Low`, `High`, `Ord`, `Succ`,
`Pred` all match. FPC picks the smallest integer type that spans the declared
range (Byte for `0..255`, ShortInt for `-5..5`, and so on); pxx gives every
subrange the 4-byte default.

## Why it is a compat item and not a bug

Nothing computes a wrong answer, and pxx is self-consistent: a program that only
ever reads and writes its own subranges cannot observe this. What it does cost:

- **binary interop** — a `packed record` written by an FPC program and read by a
  pxx one (or a `file of TR`, or a struct handed to C) has a different layout;
- **memory** — 4x for a large array of subranges, which is the whole reason a
  program declares `array[0..N] of 0..255` rather than `array of Integer`.

Both are real, and neither is silent wrong arithmetic, so this stays a compat
ticket rather than escaping to a `bug-` one.

## Sketch

The size decision wants the same treatment `AliasIsSub` / `AliasSubLo` /
`AliasSubHi` already give the bounds: pick the narrowest ordinal spanning
`lo..hi`, signed when `lo < 0`. The hazards are the ones the narrowing-cast work
already mapped — a narrower field means a narrower LOAD, so anything that
re-tags a load in place has to widen the value rather than the access (see the
notes in `ir.inc`'s `AN_PTR_CAST` arm) — and the range-check path, which must
keep using the DECLARED bounds, not the storage type's.

## `string[N]` caps the length but is not a shortstring

*(was `compat-pascal-string-n-is-not-a-shortstring`, prio 25)*

# `string[N]` caps the length but is not a shortstring

- **Track P** (Pascal frontend: the `string[N]` type), tag **compat-pascal**.
- Found 2026-08-20 by an FPC differential probe over strings.

## What differs

```pascal
type TS20 = string[20];
var ss: TS20;
begin
  ss := 'hello';
  Writeln(Length(ss), ' ', SizeOf(ss), ' ', Ord(ss[0]));
end.
```

| | FPC 3.2.2 | pxx |
| --- | --- | --- |
| `Length(ss)` | 5 | 5 |
| assignment past the cap truncates | yes | yes |
| `SizeOf(ss)` | 21 | **8** |
| `Ord(ss[0])` (the length byte) | 5 | **0** |

Everything about the CHARACTERS agrees — assignment, truncation at 20,
indexing from 1, mutation through `ss[1]`, passing by value. What does not is
the storage: FPC lays a shortstring out as one length byte followed by N
characters, in place; pxx uses its managed string with a declared cap, so
`SizeOf` reports a handle and the `s[0]` length-byte idiom reads nothing.

## Why it is a compat item

`s[0]` is a Turbo Pascal idiom that FPC still honours and that real code does
use, but reading it here answers #0 rather than a wrong length, so a program
that uses it gets an obviously-empty answer rather than a plausible one. The
layout difference matters for the same reasons as
[[compat-pascal-subrange-storage-size]]: a record with a `string[N]` field, a
`file of TRec`, and anything handed to C see a pointer where FPC puts N+1
bytes in place.

Recorded rather than scheduled: making `string[N]` a real in-place shortstring
is a storage-model change, and the dialect deliberately has ONE string model.
The decision of whether to grow a second one belongs to Track U if it is ever
worth it.

## A `string[N]` field makes a record a different size than FPC's

*(was `compat-pascal-a-string-n-field-makes-a-record-a-different-size-than-fpc`, prio 25)*

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
