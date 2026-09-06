---
track: P
prio: 35
type: bug
blocked-by: [decide-how-a-type-carries-an-identity-its-kind-cannot-hold]
summary: "CLOSED 2026-09-06: all thirteen builtin type names now answer at every door. The last rows were `High`/`Low` of the four sized booleans -- ByteBool, WordBool, LongBool, QWordBool -- refused at the DIRECT spelling and, through a one-line alias, first answering a silent wrong bound (255 / 65535 / 2147483647 from the C-ABI kind) and later refusing too. Answered now from the IDENTITY table rather than the kind table: `SizedBoolBound` in pasparser_lval.inc, wired at both High/Low resolvers and at both spellings. High is True (Ord -1), Low is False (0). THOSE VALUES ARE OURS AND CHOSEN -- fpc 3.2.2 gives the Int64 extremes for all four widths, its own assembler refuses the value it produced, and `Ord()` truncates them to exactly the -1/0 we return, so every earlier reading of fpc here was the wrong instrument. Test `test/test_high_low_of_a_sized_boolean.pas`, 37 rows, both spellings, six controls."
status: done
owner: "frankB"
---

# One name, several doors, and the working ones vouch for the broken ones

The Pascal frontend recognises a builtin type NAME at several independent
places — the declaration path, the cast doors, `SizeOf`, `High`/`Low`,
`TypeInfo` — each with its own recognition rule. The expensive failure is not
two doors disagreeing about a VALUE. It is one name working at some doors and
being refused at others, because **every working door tells you the name is
fine**, and a name with synonyms hides it completely: `SizeUInt` cast and
`SizeOf`d correctly for months while `High(SizeUInt)` said *undefined variable*,
and its three synonyms `SizeInt` / `NativeUInt` / `PtrUInt` all worked
(`ecb00083e`).

Measured at `1df943481` over all 51 names in the union of `OrdinalNameToTk` and
`BuiltinScalarTypeKind`, `{$mode delphi}`, both compilers, seven doors each
(declaration, `SizeOf(T)`, a cast stored in its DECLARED type, the cast's value,
`High`, `Low`, `TypeInfo`) — 314 cells agree, 23 differ:

| name(s) | refused at | fpc 3.2.2 answers |
| --- | --- | --- |
| ~~`WideChar` `UnicodeChar` `UCS4Char`~~ | ~~`High` `Low`~~ | **FIXED** — see below |
| `ByteBool` `LongBool` `WordBool` | `High` `Low` | `TRUE` / `FALSE` |
| ~~`AnsiString` `RawByteString` `UnicodeString` `UTF8String` `WideString`~~ | ~~`Low`~~ | **FIXED** — see below |
| ~~`Variant` `OleVariant`~~ | ~~the cast~~ | **FIXED** — and it was a SEGFAULT, not a refusal |

**EDGE ADDED 2026-09-06 (frankA), and it is the whole remainder.** This was
`blocked-by: []` while its own summary said the three surviving rows need a kind
the current tables cannot express — which is the fork
`decide-how-a-type-carries-an-identity-its-kind-cannot-hold` exists to settle.
The prose said it and the frontmatter did not, so the ranker could not see it and
`ready --track P` would have handed the row to someone who then hit the fork with
ten of the thirteen already done. Membership stated in prose and absent from
frontmatter is the one place the ranker cannot look. Its sibling consumer,
`feature-p-the-booleannn-family-of-explicit-width-boolean-type-names`, was wired
to the same fork this morning for the same reason.

**The sized booleans are the interesting one and they are NOT a one-liner.**
They map to `tyUInt8` / `tyInteger` / `tyUInt16` on purpose, to keep their C-ABI
WIDTH, and `High`/`Low` read that kind — so simply teaching `OrdinalNameToTk`
about them would answer `High(LongBool) = 2147483647` instead of `TRUE`. They
need a kind that carries a width AND boolean bounds, which the current table
cannot express. Measured before rejecting the delegation, not after.

**The string `Low` rows are probably one fix**, and `High` already works for
all five, so whatever answers `High` has the name and declines the sibling.

**Not filed as five tickets** because the shape is one: a per-door recognition
rule that was correct for the names its own tests used. Whoever takes this
should run the probe first — it is the only instrument that can see the class,
since a per-door test passes on every door that works.

## 2026-09-06 (frankA) — the refusal is one spelling, and the other spelling answers wrongly

The three surviving rows are refused as `High(ByteBool)`. They are NOT refused
through a one-line alias, and there they answer an ordinal:

| | `High` | `Low` | fpc, both spellings |
| --- | --- | --- | --- |
| `High(ByteBool)` | REFUSED | REFUSED | `TRUE` / `TRUE` |
| `type b = ByteBool; High(b)` | **255** | 0 | `TRUE` / `TRUE` |
| `type b = WordBool; High(b)` | **65535** | 0 | `TRUE` / `TRUE` |
| `type b = LongBool; High(b)` | **2147483647** | -2147483648 | `TRUE` / `TRUE` |

**THE REFUSAL IS THE MITIGATION AND THE ALIAS ROUTES AROUND IT.** This ticket's
own body says these names map to `tyUInt8`/`tyInteger`/`tyUInt16` on purpose, to
keep their C-ABI width, and that answering `High` from the kind would give
2147483647 rather than TRUE — which is exactly what the alias spelling does. So
the direct door is not merely missing a feature; it is declining to answer a
question it cannot answer correctly, and the sibling door has no such scruple.
A refusal is loud and a wrong bound is silent, which makes the accepted spelling
the worse of the two.

**It also changes what is BLOCKED.** Making these answer `TRUE` needs the kind
that carries a width and boolean bounds together — the fork this ticket is now
edged to, and genuinely blocked. Making the two spellings AGREE does not: the
alias path could refuse exactly as the direct path does, today, and that is a
strictly smaller change than the fork. Whoever takes the fork should know they
are not the only route.

**The population this was found in, and what it certifies.** All 51 names from
the union of `OrdinalNameToTk` and `BuiltinScalarTypeKind`, derived from the
tables rather than read off a list, each asked in BOTH spellings — the builtin
name and a one-level `type a = <name>` alias to it — in one program per door:

- `SizeOf`, all 51 names, pxx and fpc: **zero** direct-vs-alias disagreements in
  either compiler. The four pxx-vs-fpc rows (`extended`/`valreal` 8 against 10,
  `variant`/`olevariant` 16 against 24) are identical on both spellings, so they
  are representational latitude and not door divergences.
- `High`/`Low`, the 31 ordinal names with the three sized booleans excluded:
  **zero** disagreements.
- `TypeInfo`, 10 names: zero.

**So the sized booleans are the ONLY cell in the sweep where the spelling
changes the answer, and the negative result is the useful half:** at `SizeOf`,
`High`, `Low` and `TypeInfo` the alias is resolved to its target BEFORE the name
is asked about, so those doors have one recognition rule and not two. The
per-door duplication this ticket is named for is real at the CAST doors — where
it produced seven defects on 2026-09-06 — and does not extend to the rest.

**What the sweep held constant, since a clean result is only about its own
axis:** alias DEPTH is one level throughout (never an alias to an alias), the
target is always a builtin (never a user record or enum), and every alias is
declared in the same program's single `type` block. A two-level alias, or one
crossing a `uses` boundary, is unmeasured.

## Guard

`tools/type_name_every_door_probe.py`, indexed in
`devdocs/dev/differential-probes.md`. Both controls are branched on:
`zzznosuchtype` must be refused at every door by both compilers, and `integer`
accepted at every door by both. Without the first, a probe where every program
fails to build reports a clean agreement on every row.

**`{$mode delphi}` is load-bearing in that probe and it is why the first run was
wrong.** Without a mode directive fpc compiles in mode `fpc`, where `Integer` is
a SMALLINT — the first run reported `SizeOf(Integer)` as `4|2` and
`High(Integer)` as `2147483647|32767` and they read as three defects. They were
one missing line, and the oracle was answering honestly about a different type
than the one pxx means.

## Related

- `refactor-p-five-dispatch-sites-for-one-named-type-cast` — the same subsystem
  from the CAST side. This ticket is the other half: that one is about several
  doors for one operation, this one about one name across several operations.
- `bug-a-the-builtin-type-name-table-exists-twice-and-the-two-disagree` — the
  ancestor. The two tables no longer disagree on a shared name (measured); they
  differ only by which names each HAS, which is what produces these rows.


## 2026-09-06 (frankA) — three of the thirteen were one missing case arm

`OrdinalTypeBound` (`pasparser_lval.inc`) folds `High`/`Low` of a builtin
ordinal, as a `case` over kinds. It had `tyChar` and `tyUInt16` and **no
`tyWideChar` or `tyUCS4Char`** — and returning False there is read by
`TryFoldHighLowType` as *"not an ordinal type NAME at all"*, so it fell through
to the variable path and reported `undefined variable (WideChar)`. The name was
recognised by `OrdinalNameToTk` and discarded one call later.

**The case was COMPLETE when it was written.** A `WideChar` variable was
`tyUInt16` then — which is listed, and 65535 is `tyUInt16`'s right answer — and
a `UCS4Char` was a 32-bit integer kind. The fix that gave each its own kind took
it out of this case without editing it, and the case still reads as correct.
Third and fourth instance of that in one session; the two others were
`IRVariantUnboxKind` and ir.inc's variant-unbox helper dispatch (`a3933d0f7`).

`High(UCS4Char)` is **1114111** (`$10FFFF`, the largest Unicode code POINT),
which is fpc's answer and NOT the 4294967295 that deriving the bound from its
4-byte storage would give. Asserted deliberately: a row whose expected value
equals what the machinery would produce by doing nothing cannot fail.

Test `test/test_high_low_of_the_carved_out_char_kinds.pas`, `.expected` from
fpc, with `Char`/`Word` control rows through the same case and the const-fold
path pinned beside the expression one (they are documented as changing
together). Positive control is pin v404, which fails with
`High/Low in a constant expression: expected an ordinal type name`.

**Ten left, and the sized booleans are still the hard one** — they need a kind
carrying a width AND boolean bounds, which no current table can express.


## 2026-09-06 (frankA) — five more, and the mechanism was already there in a sibling spelling

`Low(s)` on a string VARIABLE has always answered 1 (0 for a frozen string),
through ParseFactorCore's `hlIsAnsi` / `hlIsFrozen` arms. Only the TYPE-NAME
spelling of the same fact was missing. Not a missing mechanism — a missing
*caller*, which is the shape that reads as the harder ticket and is the easier
one.

One shared `StringTypeBound`, asked at SIX sites: the `string` keyword, a
builtin name, and a user alias, each in the expression resolver and the
constant one. Six rather than a pair because those two resolvers are already
documented in the source as one concept in two places that must change
together, and four unshared arms is exactly how the ordinal arms beside them
drifted.

**`High` of a managed string stays refused, and that is fpc's asymmetry.** fpc
3.2.2 answers `High(ShortString)` = 255 and `High(S10)` = 10 for
`S10 = string[10]` — both now answered here, from `AliasStrCap` — and REFUSES
`High(AnsiString)` / `High(string)` with *"type identifier not allowed here"*,
because a managed string has no upper bound. All seven spellings measured
before the helper was written.

**The row that caught the first version of the fix** is worth keeping: it passed
`tyString` to the helper, and `TypeIsFrozenString(tyString)` is TRUE — it is the
legacy overloaded frozen kind — so `Low(string)` answered 0 while
`var s: string; Low(s)` answered 1. The keyword now resolves through
`ParseTypeKind`, the way a declaration does, and the test keeps that row beside
its variable twin: apart, neither can show the disagreement.

**Five left at the time of writing** — superseded by the entry below, which is
the clean re-run. The numbers in this block came from a run whose binary moved
underneath it; kept because the contamination is the lesson, not the counts:

```
bytebool    refused at: high low
longbool    refused at: high low
wordbool    refused at: high low
variant     refused at: cast
olevariant  refused at: cast
names=51  cells-agree=323  cells-differ=14
```

**The fix produced a new PHANTOM row in the probe and it is worth recording,**
because it is the shape a probe goes quietly wrong in. Once `High(WideChar)`
stopped being refused, the probe's `WriteLn(High(WideChar))` started measuring
the OUTPUT ENCODING — pxx emits the UTF-8 bytes of U+FFFF, fpc emits `?` — and
the cell flipped from `PXX-REFUSES` to `DIFFER`. **The confound was there all
along and the refusal was hiding it.** The probe now prints the char kinds'
bounds through `Ord()`, and only those names: `Ord()` as a UNIFORM printer
would introduce a second phantom, since `Ord(q)` for a QWord answers -1 in pxx
against fpc's 18446744073709551615, which is intermediate-overload latitude and
not a defect.


## 2026-09-06 (frankA) — the Variant rows were a SEGFAULT, and three are left, measured

**`Variant(x)` was not merely refused at the cast door — it crashed.**
`v := Variant(y)` for `y: LongInt` segfaulted at run time while `v := y` on the
line above printed 233. The cast built an `AN_PTR_CAST` retagging the integer AS
a variant record, so the assignment saw an RHS already typed `tyVariant`,
skipped the boxing it does for the implicit form, and copied 16 bytes from
beside a 4-byte local. It yields the operand now and lets the assignment box it
(`b6815e5b8`). The probe could only see this as `PXX-REFUSES` because its cast
row stores and does not print; **a sweep's severity resolution is whatever its
assertion can observe.**

**The clean re-run, on a settled tree at `b6815e5b8`, binary `0207010e859c`
identified before and after the sweep:**

```
bytebool   refused at: high low
longbool   refused at: high low
wordbool   refused at: high low
names=51  cells-agree=327  cells-differ=10
```

Thirteen at filing, three now. The ten remaining differing cells are not
defects: `SizeOf(Extended)` 8 vs 10 and `SizeOf(Variant)` 16 vs 24 are
representational choices, which CLAUDE.md records as CHOSEN — each compiler
reporting its own representation faithfully — and `Extended`/`ValReal` casts are
`pxx-only`, us accepting what fpc rejects.

**The probe now identifies the compiler at the START and END of the sweep and
ABORTS if it moved.** The run before this one was contaminated by my own
rebuild, and the failure does not look like noise: the sweep runs in name order,
so it partitions cleanly along the ALPHABET, and it reported `olevariant`
broken and `variant` fixed — two spellings of one type, mapping to one kind,
separated by nothing but where the rebuild landed between them.

## 2026-09-06 — A FOURTEENTH NAME, AND ITS ROW SET WAS THE BLIND SPOT, NOT ITS ARMS (frankA, relayed)

`Real(d)` — a plain Double-to-Real cast that fpc compiles — was **REFUSED** with
`expected expression`, while `var r: Real` has declared fine forever. The case
label read `tkSingle_T, tkDouble_T, tkExtended_T` and **`Real` was the fourth
float keyword nobody listed.** frankA is closing it under
`refactor-p-five-dispatch-sites-for-one-named-type-cast` rather than filing
separately; recorded here because this ticket is the family and **it has
`owner: ""`**, so a message to "whoever holds it" had no reader.

**THE REASON IT WAS MISSED IS STRUCTURAL AND IT INDICTS THE TEST, NOT THE ARMS.**
Every name in `test/test_builtin_type_names_cast_and_declare.pas` is an
**IDENTIFIER**. The four float spellings are **KEYWORDS** — confirmed in
`compiler/paslexer.inc`: `real`/`Real` -> `tkReal_T` (`:125-126`),
`single`/`Single` -> `tkSingle_T` (`:170-171`), `double`/`Double` -> `tkDouble_T`
(`:172-173`), and `Extended` likewise. **A keyword-spelled type name cannot enter
a sweep whose rows are all identifiers**, so the four were outside the population
the test varies, and no amount of adding names to it would have reached them.

**Their ROW SET was the blind spot, not their arms.** A sweep certifies the axis
it varied; this one varies *which identifier*, and the defect lives on *whether
the spelling is an identifier at all*. The test now carries rows for all four.
**Anyone extending this ticket should ask what the test's rows have in common
before adding another one to the list** — that shared property is the aperture,
and it is invisible from inside a passing sweep.


## 2026-09-06 (frankB) — CLOSED. The last four rows, and every fpc value in this ticket above was read off the wrong instrument

**THE CORRECTION FIRST, because this ticket's own table is wrong and someone
implementing from it would have shipped a bug and believed they had parity.**
Every row above that records fpc answering `TRUE` / `FALSE` for
`High`/`Low` of a sized boolean was read off `WriteLn`. Measured properly on
2026-09-06 by casting to Int64 before printing:

```
Int64(High(ByteBool))   9223372036854775807      Int64(High(Boolean))  1
Int64(Low(ByteBool))   -9223372036854775808      Int64(Low(Boolean))   0
Int64(High(WordBool))   9223372036854775807
Int64(High(LongBool))   9223372036854775807
```

fpc gives **the Int64 extremes, the same pair for all four widths**, for a type
whose only values fpc itself materialises are 0 and all-bits-set — and it
answers 1/0 for plain `Boolean`, so the sized ones are the ones with no range
recorded, not a considered choice. fpc's own assembler refuses the value fpc's
front end produced: for `b: ByteBool`, `b := Low(ByteBool)` is
**"Asm: byte value exceeds bounds -9223372036854775808"**, while
`SizeOf(High(ByteBool))` answers 1. The expression has the type and the value
does not fit in it.

**WHY IT READ AS TRUE/FALSE, AND WHY THE PROBE COULD NOT FAIL.** Both `WriteLn`
and `Ord` truncate the Int64 to the type's width before you see it: 0x7FFF..FF
keeps 0xFF (−1 signed), 0x8000..00 keeps 0x00. So `Ord(High(ByteBool))` prints
−1 and `Ord(Low(ByteBool))` prints 0 — **exactly the two values we return** — and
a probe reading fpc through `Ord` reports agreement with us on a row where we
disagree completely. CLAUDE.md, *"CHOOSE A PROBE WHOSE RIGHT ANSWER DIFFERS FROM
THE DEFAULT"*. The one row that survives truncation is
`WriteLn(Low(ByteBool))` printing **TRUE** in fpc while its own `Ord` is 0 — a
self-contradiction inside one compiler's output, and the tell that was visible
all along.

The same wrong reading was in `OrdinalNameToTk`'s comment (*"it answers TRUE for
ByteBool/LongBool/WordBool"*); corrected in the same commit, with the method
written down beside it so the next reader does not repeat it.

**WHAT WE ANSWER, AND IT IS CHOSEN.** `High` is True (all bits set, Ord −1),
`Low` is False (0) — the bounds of the type the caller named, storable in a
variable of it, and what `for b := Low(ByteBool) to High(ByteBool)` means.
CLAUDE.md, *"ON PAR WITH THE LANGUAGE, NOT WITH FPC"*: an input whose fpc answer
does not fit the type it is an answer about is not a specification. Recorded as
**chosen, never tolerated**.

**THE MECHANISM WAS ALREADY BUILT AND HIGH/LOW SIMPLY NEVER ASKED IT.** This
ticket says four times that the sized booleans *"need a kind that carries a
width AND boolean bounds, which no current table can express"* — and that is
still true and no longer the obstacle. The width lives in the kind
(`tyInt8/tyInt16/tyInteger/tyInt64`, the C-ABI mapping) and the booleanness
lives in the SemId channel beside it (`BuiltinScalarSemId`, `SemBool(1/2/4/8)`),
which `decide-how-a-type-carries-an-identity-its-kind-cannot-hold` settled and
which the declaration path has used since QWordBool joined. **High/Low read only
the kind.** `SizedBoolBound` asks the identity table and derives the storage
kind back from the width it returns, so both halves of the answer come from one
row. No new table, no new kind — the fork this ticket was `blocked-by` had
already been resolved in its favour.

**BOTH SPELLINGS, AND THE ALIAS ARM HAD BEEN WRONG IN TWO DIFFERENT WAYS.** The
frankA note above records `type b = ByteBool; High(b)` answering **255** — a
silent wrong bound beside the direct spelling's loud refusal. That is no longer
what it does: by the time this was taken it had become a **refusal** as well,
because an alias carries its identity in the same `AliasSemId` slot an ENUM
alias uses, so the boolean sem was read as an enum id and `FindEnumType` missed
it. Both failure modes are fixed by the same `SizedBoolSemBound`, which is the
name-keyed helper's sem-keyed half — one set of values, four call sites (two
resolvers × two spellings), which is the shape `StringTypeBound` next door
already has and for the same stated reason.

**Verified:** `make compiler/pascal26` → `converged after 1 round(s)`;
`test/test_high_low_of_a_sized_boolean.pas` green, 37 rows —
eight direct High/Low, four `SizeOf` (1/2/4/8, matching fpc, which gets this
half right), four `Str` rows that assert the value renders TRUE/FALSE and not
−1/0, **five assignment rows that fpc cannot compile at all**, three const-door
rows (a second resolver, not the same code), eleven alias rows, and six
controls (`Boolean` 1/0, `Byte` 255, `LongInt`, `ShortInt` 127/−128) because
the new arm sits in the slot the ordinal table is read from.

**No `.expected` from fpc, deliberately** — the values are ours and five rows do
not compile there. Noted in the Makefile beside the target so nobody adds one.

**Residual, and it is genuinely nothing:** the probe
`tools/type_name_every_door_probe.py` still prints these rows through `Ord()`,
where fpc's truncated −1/0 now MATCHES ours. It will report agreement, which is
the right verdict reached by the wrong arithmetic. Left as is rather than
"fixed": changing it to cast through Int64 would make the sweep report a
DIFFER on four names that are correct and chosen, which is worse.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
