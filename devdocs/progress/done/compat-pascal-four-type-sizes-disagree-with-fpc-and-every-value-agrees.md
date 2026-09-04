---
summary: "ONE OF THE THREE IS DONE. **Subranges are now stored in the narrowest ordinal that spans the declared range** -- SizeOf(0..255) and SizeOf(-128..127) are 1, `packed record a,b,c` is 3, `array[0..3] of 0..255` is 4, all matching FPC 3.2.2, on x86-64 and on i386/aarch64/arm32/riscv32 byte-identically. AND IT WAS NOT A FOOTPRINT ITEM: `TBig = -3000000000..3000000000` was given four bytes, so storing -3000000000 read back **1294967296** -- ordinary declared source, no diagnostic, wrong number, reproducible on the pin. STILL OPEN, and they do not share a cause: (2) THE SET THIRD HAS MOVED OUT to [[bug-a-a-set-is-32-bytes-whatever-its-bounds-and-the-ir-opcode-says-so]] (Track A) -- it is a codegen/ABI slice, not a Pascal sizing one, and bundled here it inherited a tractability the string half earned; (3) `string[10]` is 8 bytes, POINTER SIZE, where FPC gives 11 inline, so a short string is not stored inline at all -- a wrong REPRESENTATION rather than a generous width, and the ticket body routes that one to Track U as a storage-model decision -- SUPERSEDED: that decision is TAKEN and item (3) is the declared deliverable of [[feature-p-implement-the-real-tyshortstring-byte-prefix-layout]] (p100, phase 2 done, seven backends emitting a one-byte prefix under -dPXX_SHORTSTRING). Now `blocked-by` it, because until 2026-09-03 this ticket was the #1 item on `ready --track P` at effective p75 with no edge to it, and its only remaining item IS the flip -- which the OWNER has reserved and nobody may start. Blocks feature-pascal-typed-and-untyped-files [p70]: `file of T` writes record layout to DISK, so layout stops being an intermediate and becomes the value."
type: bug
track: P
prio: 25
blocked-by: [feature-p-implement-the-real-tyshortstring-byte-prefix-layout]
---

> **`prio: 25` is correct and must not be raised to match the ranked output.**
> This ticket shows as **P p70** in `ready`/`next`, and the gap is not a mistake:
> effective rank is a human `prio:` **propagated down dependency edges**, so a
> blocker inherits the priority of what it unblocks. The single edge is
> [[feature-pascal-typed-and-untyped-files]] [P p70], whose frontmatter declares
> `blocked-by` on this ticket. `file of T` is standard Pascal that real code uses
> heavily, so p70 is right *for that goal*, and this ticket inherits it.
>
> **25 is this ticket's own intrinsic worth** — verified 2026-08-30, see the note
> at the bottom: nothing in pxx computes a wrong value, `packed` is honoured, and
> the byte-exact layout is expressible today with explicit widths. Editing either
> number to make them agree is the tempting wrong move: raising `prio:` overstates
> the intrinsic worth, and lowering the goal drops a genuine p70 feature out of
> the queue. Leave both; the ranker is doing what it was built to do.
>
> Direction is settled too: sizes come **before** a typed-file on-disk format,
> because settling layout afterwards would silently invalidate written data.

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
bytes per set matters. Do it together with the **subrange** half — which is not a separate ticket to
coordinate with, it is the *"A subrange type is always 4 bytes"* section of THIS
file, absorbed here and still carrying its old slug at the section head. They are
the same job (storage size from the declared range) over two type constructors,
and doing one alone leaves half the layouts still divergent.

*(De-linked 2026-08-30. `compat-pascal-subrange-storage-size` resolved to no
ticket because it was merged INTO this one — so this document was citing itself
as a separate dependency it needed to coordinate with. A merge that keeps the
absorbed ticket's citations converts them all into dangling links pointing at a
section of the citing file; that is a fifth outcome beside rename, never-filed,
delivered-under-another-name and never-was-a-ticket, and it is the only one where
the answer is already in the reader's hands.)*

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
layout difference matters for the same reasons as the subrange section above
(merged in from `compat-pascal-subrange-storage-size`, hence no longer a link): a record with a `string[N]` field, a
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
- **Status:** done
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

---

## Verification 2026-08-30 (frankA) — measurement only, no fix, no claim

Re-measured at HEAD `3309b9ba6609` against `fpc -O- -Mobjfpc` 3.2.2, because
this repo's tables go stale and this one is from 2026-08-16/20. **It does not:
every row still holds**, and `lenbyte` is now 5 on both sides — the one row this
ticket already records as closed.

```
                    pxx   FPC
set8                 32     4
set031               32     4
setbyte              32    32
recset               48    12
small                 4     1
neg                   4     1
big                   4     4
packedrec            12     3
arr                  16     4
strN                  8    21
lenbyte               5     5   <- closed row, agrees
recstr               24    11
recstri              24    16
```

### Asked to route this bug-vs-defer. It is **neither row**, and the reason matters

CLAUDE.md's bug row is *"real Pascal source compiles but runs wrong."* Measured
against pxx **alone**, with no oracle in the program, nothing runs wrong:

- **`packed` is honoured.** `packed record a: TSmall; b: TNeg; c: 0..255` has
  field offsets 0/4/8 and `SizeOf` 12, which is exactly the sum of its field
  sizes — **no padding**. pxx is not failing to pack; its subrange fields are
  simply 4 bytes wide.
- **The byte-exact layout is expressible today.** `packed record a: Byte;
  b: ShortInt; c: Byte` is **3** in pxx, matching FPC. Code that needs a
  wire-exact or struct-exact layout writes explicit widths — which is what such
  code already does — and it works.
- **pxx round-trips its own bytes.** `Move(r, r2, SizeOf(TRec))` on a record
  with a `string[10]` field preserves both fields.

So the cost is real but it is **memory footprint (4x on subrange arrays, 8x on
small sets) and cross-toolchain layout**, not a wrong answer. Equally it is
*not* the defer row — that row is for diagnostics and rendering, and storage
size is neither. It is an ordinary compat item, and **its filed `prio: 25` is
right on its own merits.**

### The p70 is borrowed, and the lender is inside the loan

This ticket shows as **P p70** only by propagation: the sole edge is
[[feature-pascal-typed-and-untyped-files]] [P p70], whose frontmatter carries
`blocked-by: [compat-pascal-four-type-sizes-...]`.

That matters because **this ticket's strongest argument for mattering is a
`file of TRec`** — *"a program that writes a record to a file and reads it back
with FPC gets garbage"* — and `file of T` **does not exist**: it is refused
outright with *"file types are not supported (use TextFile for text I/O)"*,
which is precisely what that other ticket is for. Measured, not assumed; it is
what made the round-trip probe above use `Move`.

So the two tickets hold each other up. Neither is independently urgent, and the
one that makes the other look urgent is blocked on it. **Not asserting the edge
is wrong** — sequencing sizes before a typed-file on-disk format is a defensible
call, since settling layout afterwards would silently invalidate written data.
Flagging it as the thing to decide, because it is what is putting a prio-25
compat item at the head of Track P.

No files touched outside this note.

## Re-measured 2026-09-02 — and it is three issues, not one family

Owner, reading the original bundle: *"we dont define TSmall and TNeg as byte
sized. that's indeed an issue. and sets not being bitpacked is also inefficient
... those are actually OTHER issues."*

Measured at `27e983d24`, compiler sha256 `468194333634`:

```
TSmall = 0..255      SizeOf 4    fpc 1
TNeg   = -128..127   SizeOf 4    fpc 1
set of 0..7          SizeOf 32   fpc 4     <- BITPACKED ALREADY; the 32 is a fixed 256-BIT WIDTH, and the `fpc 1` this row used to read was never measured
string[10]           SizeOf 8    fpc 11    <- POINTER size
record of 2 subrange SizeOf 8    fpc 2
```

**These do not share a cause and should not share a ticket:**

1. **Subranges are not narrowed to their range.** A type declared `0..255` is
   stored in 4 bytes. Wasteful, and it makes every record containing one wider
   than the language implies.
2. **CORRECTED 2026-09-02 — sets ARE bitpacked, and this row was wrong twice.**
   `set of 0..7` takes 32 bytes, which is 256 BITS: one bit per ordinal over the
   whole 0..255 range, not a byte per element. `defs.inc:2003` defines the kind
   as `{ 21: Set — 32-byte bitset }` and `IR_SET_LIT` bakes a *32-byte mask*.
   The defect is that the width does not follow the DECLARED BOUNDS, not that
   the bits are unpacked. FPC is 4 here, not 1. Moved out to
   [[bug-a-a-set-is-32-bytes-whatever-its-bounds-and-the-ir-opcode-says-so]] —
   a 32x waste that is an efficiency defect on its own terms, independent of any
   FPC comparison.
3. **`string[10]` is 8 bytes: POINTER SIZE.** So a short string is not stored
   inline at all. **This is NOT fixed** — worth stating plainly, because assuming
   it was is the natural reading of "SizeOf reports pointer size" appearing
   beside two genuine layout choices. It is a different animal from (1) and (2):
   they are widths chosen too generously, this is the wrong REPRESENTATION.

**Why none of them is `known-incompat/`.** The folder needs no program to observe
a wrong value. `file of T` writes record layout to disk, so here the layout IS
the value — and (3) means writing a pointer where FPC writes eleven characters.
The original body already reached this conclusion by a different route: settle
sizes before an on-disk format, or silently invalidate written data.

**Splitting is left to whoever takes it**, deliberately: this ticket carries the
`blocked-by` edge from `feature-pascal-typed-and-untyped-files`, and re-wiring
that graph half-done is worse than a bundle that says it is a bundle.


---

## 2026-09-02 (frankB) — the SUBRANGE third is FIXED, and it was a wrong-value bug

Landed. `SubrangeStorageTk(lo, hi)` in `pasparser_decl.inc` picks the narrowest
ordinal spanning the declared range — unsigned when `lo >= 0`, signed otherwise
— and **both** parser arms call it: the named `T = lo..hi` in `ParseTypeSection`
and the inline `var x: lo..hi` in `ParseTypeKind`. They are two spellings of one
construct, and `normalise-dont-special-case` is exactly the trap here: fixing
one alone leaves the other broken for months while the headline case works.

Measured at `a1e916acf`, compiler `ea9f0ee2a3b7`, oracle `fpc -O- -Mobjfpc` 3.2.2:

| | before | after | FPC |
| --- | ---: | ---: | ---: |
| `SizeOf(0..255)` | 4 | **1** | 1 |
| `SizeOf(-128..127)` | 4 | **1** | 1 |
| `SizeOf(10..20)` | 4 | **1** | 1 |
| `SizeOf(0..70000)` | 4 | 4 | 4 |
| `packed record a: 0..255; b: -128..127; c: 0..255` | 12 | **3** | 3 |
| `array[0..3] of 0..255` | 16 | **4** | 4 |

### It is not a compat item. It computed a wrong value

The pre-existing behaviour gave EVERY subrange four bytes, including ones whose
declared range does not fit in four bytes. On the pin:

```pascal
type TBig = -3000000000..3000000000;
var g: TBig;
begin g := -3000000000; WriteLn(g); end.
```

    pin      1294967296     SizeOf 4
    fixed   -3000000000     SizeOf 8
    fpc     -3000000000     SizeOf 8

Ordinary declared source, clean compile, no diagnostic, wrong number. That row
is why this third is a `bug-` and not the `compat-` its ranking assumed — and it
is the row that nobody measured, because every probe in this ticket's history
used ranges that happen to fit.

### What was NOT changed, deliberately

The **declared bounds stay a separate fact.** `AliasSubLo`/`AliasSubHi` (named)
and `LastTypeSubLo`/`LastTypeSubHi` (inline) still drive `{$R+}`, `Low`, `High`,
`Ord`, `Succ`, `Pred`. `10..20` stores in a byte and still answers 10 and 20,
not 0 and 255, and `{$R+}` still rejects 201 for a `0..200`. Both verified
against FPC, including that `{$R-}` truncation matches FPC exactly and `{$R+}`
exits 201 on both.

A **char subrange keeps `tyChar`** — its storage is already one byte and its
values must stay chars.

The result is an **ordinary ordinal kind**, not a new subrange kind: `tyUInt8`
is what `Byte` already resolves to, so every load, store, widen, compare and
record-layout path this reaches is one the compiler already exercises. That is
what made this a sizing change rather than the codegen slice the ticket feared.

### Verification

- `test/test_subrange_storage.pas`, wired into `test-core`, output byte-identical
  to FPC 3.2.2 across 14 rows.
- **Positive control**: with the two narrowing calls removed and the compiler
  rebuilt, the test goes red on the size rows (`4 4 4 4 4` vs `1 1 1 4 8`) AND on
  the `TBig` value row. Restored and re-verified byte-identical.
- **Cross targets**: i386, aarch64, arm32 and riscv32 each produce output
  byte-identical to x86-64 and to FPC. The ticket's Gate asks for this
  specifically, because a size change is where a suite goes green while the ABI
  moves underneath it.
- Self-host fixedpoint converged; `gate.sh quick` GREEN with the FPC seed canary
  RUN rather than SKIPped; `--tier quick` GREEN.

### One correction to this ticket's own 2026-09-02 note

It records `set of 0..7  SizeOf 32  fpc 1`. FPC 3.2.2 answers **4**, not 1 —
measured again here, and the ticket's ORIGINAL table (2026-08-20) says 4 in
every row too. The 32x figure in the prose is right; the `fpc 1` is a typo that
would send whoever implements bitpacking after a one-byte target FPC does not
use. FPC sizes a set by its element range **with a 4-byte floor**.

#### It was not a typo, and the distinction is the point (frankuser, 2026-09-02)

It was an **unmeasured assumption printed in a measured column.** The probe that
produced that block was a pxx program whose expectation strings were typed by
hand:

```pascal
WriteLn('set of 0..7     ', SizeOf(TS), '   fpc 1  (bitpacked)');
```

`SizeOf(TS)` was measured. `fpc 1` was **written into a WriteLn** by someone who
had not run FPC, and it came out of the same program, in the same column, in the
same font as the number that was real. Then it went into this ticket's summary as
fact. **FPC was never run at any point.**

A typo is a slip that proofreading catches. This is the failure CLAUDE.md already
names — *a verification claim scopes to exactly what was checked, and an
unlabelled claim travelling beside it inherits that credibility* — and the
correction is not "be careful", it is **do not put a number you did not measure
in the same output as one you did.** If an oracle column cannot be produced by
running the oracle, it must be left blank or marked `assumed`.

The two subrange rows in that block have the same defect and were right by luck.
The `string[10] fpc 11` row is the same and is still unverified against FPC.



## 2026-09-02 (frankB) — measuring the `string[N]` third turned up a separate BUG

Not this ticket's issue, fixed separately, but whoever takes the representation
decision needs both facts:

**1. `SizeOf` was answering the pointer width for every `string[N]`** — all seven
shapes — while the layout engine gave that type cap+8. `SizeOf(array[0..2] of
string[10])` was 24 with the elements 18 apart, so `FillChar(a, SizeOf(a), 0)`
cleared 24 of 54 bytes. Fixed at `be76fab5a`,
[[bug-p-sizeof-answers-pointer-width-for-a-string-n-that-occupies-more]]. That
was SizeOf disagreeing with **our own storage**, not with FPC, so it was wrong
under either answer to the question below and fixing it prejudges nothing.

Note the trap it leaves behind: for `string[7]` specifically, the WRONG answer
(pointer width, 8) equals FPC's RIGHT answer (7+1, 8). A test had frozen that 8
and read as agreeing with FPC while agreeing with nothing in memory.

**2. The representation decision is cheaper than this ticket assumes.**
`tyShortString` ALREADY EXISTS and `FrozenStrSlotSize` already returns cap+1 for
it — the split is live, and `string[N]` simply maps onto `tyFixedString`
(8-byte length word) instead. So this is plausibly a mapping change plus its
consequences, not a new storage kind. Measured, not read: `string[10]` is 18
bytes here and 11 under FPC, and the length word is what differs.

Contrast with the SET third, which really is a Track A codegen/ABI slice: 115
`tySet` sites, 32 bytes baked into every backend, the by-value ABI class,
`IR_SET_COPY`/`IR_SET_LIT`, constant baking and default parameters. The two
remaining thirds are NOT the same size of job and should not be ranked as one.

## Why the `blocked-by` edge was added, 2026-09-03 (frankA)

Item (1) is done, item (2) moved out to its own Track A ticket, so **everything
still open here is item (3)** — and item (3) is not a Track P sizing question
any more, it is `feature-p-implement-the-real-tyshortstring-byte-prefix-layout`,
whose definition of done is exactly "`string[N<=255]` is a real byte-prefixed
`tyShortString`". The edge is therefore exact, not approximate: no part of this
ticket can be finished before that one lands.

It was load-bearing and not paperwork. Measured before the edit: this was the
**top row of `ready --track P`** at effective p75 (own prio 25, inherited from
`feature-pascal-typed-and-untyped-files` p70 and `umbrella-sizeof-is-one-answer`
p75 through two separate paths). A Track P agent pulling the top of its own
queue was being handed the flip — the one piece of work the owner has kept for
himself and which serialises the fleet.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

## Closed 2026-09-04 — all three items settled, measured not inferred

Measured at HEAD `0d090cd1d`, compiler sha256 `1968c7a7da57`, from a real
`converged after 2 round(s)` build (not the stamp path):

```
SizeOf(string[10]) = 11        <- item (3), was 8 (pointer size)
SizeOf(TBig)       = 8
TBig roundtrip     = -3000000000   <- the wrong-number defect, was 1294967296
SizeOf(0..255)     = 1
SizeOf(-128..127)  = 1         <- item (1)
len/str            = 3 abc
```

- **(1) subranges** — done before this session, re-confirmed above.
- **(2) sets** — deliberately out of scope, living in `rainy-day/` as
  [[bug-a-a-set-is-32-bytes-whatever-its-bounds-and-the-ir-opcode-says-so]].
- **(3) `string[10]` inline** — delivered by the flip. Its blocker
  [[feature-p-implement-the-real-tyshortstring-byte-prefix-layout]] is in
  `done/`, `-dPXX_SHORTSTRING` is deleted, and the size is 11.

This ticket's own summary said its only remaining item WAS the flip. The flip
landed, so there is nothing left to do here. Closing it unblocks
[[feature-pascal-typed-and-untyped-files]], which is still open.

**A note on why this was nearly mis-filed, because the trap is in the title.**
It was flagged to me as a likely `known-incompat/` candidate on the strength of
its own name — *"and every value agrees"* — which reads exactly like CLAUDE.md's
implementation-latitude class. The body says the opposite: `TBig` stored
-3000000000 and read back **1294967296**, ordinary declared source, no
diagnostic, wrong number, reproducible on the pin. That is a defect by any
reading, and it was real until it was fixed. **A title is a claim from the day
it was written and nothing updates it** — this one described the ticket's
framing at filing and survived a correction in its own body. Had it gone to
`known-incompat/` on the title, a genuine wrong-value bug would have been
recorded as a chosen divergence.
