---
slug: feature-p-packenum-and-h-minus-for-the-fpc-compiler-corpus
track: P
prio: 45
type: feature
blocked-by: []
status: done
owner: frankB
created: 2026-09-04
summary: "{$PACKENUM 1}/{$MINENUMSIZE n}/{$Zn} are IMPLEMENTED (2026-09-05): an enum type freezes its storage width at its declaration from the directive in force AT THAT TOKEN, and the width is a MINIMUM -- `(bA, bB = 300)` is two bytes under {$PACKENUM 1}, not one. Verified against a gcc -fshort-enums oracle on x86-64 AND i386 with the unpacked build as the positive control (1 2 6 1 2 4 vs 4 4 16 4 8 12), and row-for-row against fpc 3.2.2 for behaviour. The {$H-} half was MEASURED and is real -- 260 bytes vs 16 for a record with a bare string under {$mode objfpc} -- and is split out to feature-p-h-minus-makes-a-bare-string-a-shortstring, as this ticket instructed."
---

# The FPC compiler corpus asks for two layouts we do not give it

Found 2026-09-04 by frankS, the first thing the new class-1 directive warning
said out loud (`bug-p-an-unknown-compiler-directive-is-silently-ignored`).
`--mimic-fpc-compiler --target=arm32` now gets past `{$i fpcdefs.inc}` — that
was `feature-p-packrecords-c-directive` — and immediately reports:

```
$ pascal26 --target=arm32 --mimic-fpc-compiler fd.pas
pascal26:3: warning: compiler directive {$H-} is recognised but not implemented …
pascal26:9: warning: compiler directive {$PACKENUM} is recognised but not implemented …
```

`/usr/share/fpcsrc/3.2.2/compiler/fpcdefs.inc`, lines 1-9:

```pascal
{$mode objfpc}
{$asmmode default}
{$H-}
{$goto on}
{$inline on}
{$interfaces corba}

{ This reduces the memory requirements a lot }
{$PACKENUM 1}
```

`fpcdefs.inc` is included by essentially every unit of that compiler, so this is
not one file's opinion — it is the corpus-wide setting, and its own comment says
why it is there.

## Why this is worth ranking above a directive nicety

**`{$PACKENUM 1}` is a record-layout change, not a size preference.** An enum
field inside a record moves every field after it. Any pxx-compiled FPC unit that
exchanges a record with a differently-compiled one — including the shadow-RTL
boundary that `goal-compile-fpc-compiler` depends on — disagrees about where the
fields are, self-consistently, which is the failure shape that
`bug-a-pascal-nilpy-rust-and-zig-over-align-an-8-byte-member-on-i386` took a
mixed link to see.

`{$H-}` is the string default for the whole corpus; ignoring it means every bare
`string` in FPC's sources is a long string where the source said shortstring.
Whether that is a problem for pxx specifically needs measuring — pxx's string
model is not FPC's — and that measurement is half this ticket.

## Not obviously one job

They are filed together because they arrive together and from one include, not
because the fix is shared. Split if the enum half turns out to be the only real
one. Measure before scoping, the way
[[feature-p-packrecords-c-directive]] did: `{$PACKRECORDS C}` turned out to be a
no-op against our existing rule, and this pair may not be.

## Gate

A record with an enum field laid out under `{$PACKENUM 1}` matching the gcc/FPC
oracle for the same declaration, on x86-64 AND a 32-bit target — the pattern in
`test-packrecords-c-gcc-oracle`, whose positive control (a second row whose
answer must DIFFER) is the part to copy. Do not assert only that the directive
is accepted: accepted-and-ignored is the state this ticket reports.

## Related

- [[bug-p-an-unknown-compiler-directive-is-silently-ignored]] — surfaced it; the
  class-1 list is where these two names live.
- [[feature-p-packrecords-c-directive]] — the wall before this one.
- [[goal-compile-fpc-compiler]] / [[feature-mimic-fpc-compiler-define-profile]]

---

## Landed: the `{$PACKENUM}` half (frankB, 2026-09-05, compiler `89f51a99f0b3`)

The ticket said *"measure before scoping"* and *"split if the enum half turns
out to be the only real one"*. Both halves are real; the enum half is done and
the string half is [[feature-p-h-minus-makes-a-bare-string-a-shortstring]].

### The value space, measured rather than assumed

Against fpc 3.2.2 on enums whose largest member is 2 / 300 / 70000:

```
{$PACKENUM 1}  1 2 4     {$PACKENUM 8}   Illegal enum minimum-size specifier
{$PACKENUM 2}  2 2 4     {$PACKENUM 3}   Illegal enum minimum-size specifier
{$PACKENUM 4}  4 4 4     {$PACKENUM ON}  Illegal enum minimum-size specifier
NORMAL/DEFAULT 4 4 4     {$PACKENUM OFF} Illegal enum minimum-size specifier
{$MINENUMSIZE n} = {$PACKENUM n}    {$Z1}/{$Z2}/{$Z4}   {$Z+}=4  {$Z-}=1
```

**It is a MINIMUM, not a size** — `THuge` stays 4 bytes even at `{$PACKENUM 1}`.
That is the row a naive "pack enums to a byte" reading gets wrong, and a test
carrying only a 3-member enum would pass under both readings, so `TBig = (bA,
bB = 300)` is in both test files as the discriminator.

### Two things a layout-only test could not have caught

**1. The state has to be PER-TOKEN, and a one-directive file cannot show it.**
Directives run in the LEX pass, so by the time a type section parses, the global
holds the LAST `{$PACKENUM}` in the file. Every single-directive probe passes
under both readings — "value at the declaration" and "last value in the file"
are the same number — so the first eleven-row oracle table matched while the
mechanism was wrong. It took a file with TWO directives to see it, and both test
files now carry one. The fix is `TokPackEnum[]`, the shape `TokScopedEnums`
already uses.

*And the control I reached for first was itself unfalsifiable*: I checked that
`{$SCOPEDENUMS OFF}` left a later member visible, which passes whether or not
the state is positional. The discriminating direction is that the EARLIER
type's member must be INVISIBLE.

**2. Narrowing the kind silently detached the enum's IDENTITY.** Seven sites
guarded the identity stamp with `kind = tyInteger` — exact while every enum was
integer-sized, wrong the moment one was not. `WriteLn` of a packed enum printed
an ordinal instead of a member name, through a variable, a record field and a
cast, with nothing failing. The kind half is **not** redundant with `enumId >=
0` and could not simply be deleted: `set of TCol` leaves `LastTypeEnumId`
holding the ELEMENT's id, so the kind test is what stops a bitset inheriting a
member name. All seven now ask one predicate, `EnumKindMatches(tk, etid)`, which
compares against `EnumStorageTypeKind` itself rather than a list of kinds — so
there is no second table to drift, which is what `TypeIsAnyString`'s header
warns about.

### Gate

- `test-packenum-gcc-oracle` — gcc built TWICE is the oracle and its own
  positive control, since `-fshort-enums` is the same promise. x86-64 and i386:
  `packed=1 2 6 1 2 4`, `control=4 4 16 4 8 12`. **fpc could not be the 32-bit
  oracle — `ppc386` is not installed on this host — which is why the oracle is
  gcc.** The row fails if the two gcc builds agree (a non-discriminating oracle),
  if either side produces no row, or if every target skipped.
- `test_packenum` in test-core — behaviour, `.expected` is fpc 3.2.2's own
  output byte for byte. The enum NAMES in it are the part the layout test cannot
  see.
- `tools/gate.sh quick` **GREEN with the FPC seed canary PASS, not SKIP** — run
  before committing, which is the only reason it was live. It caught this
  change's real defect: three declaration-order breaks that pxx accepts and
  single-pass FPC does not.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 324641046.
