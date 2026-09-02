---
slug: bug-p-sizeof-rejects-twelve-type-names-that-a-declaration-accepts
track: P
type: bug
prio: 40
status: done
found: 2026-08-31
found-by: frank-rust
owner: unassigned
blocked-by: []
summary: "DONE. A PATTERN, not a site: a builtin type name settled against the builtin TABLE rather than against the PROGRAM. BOTH instances are fixed -- SizeOf (582e4de09) and ParseTypeKind (2ba37ba91: its guard was `FindTypeAlias(lo) >= 0` alone where SizeOf consults six tables, so an alias beat a builtin name and a RECORD did not, and `SizeOf(Currency)` on a user record answered 12 in an expression and 8 in an array bound in the same program). Of the twelve names it opened on, eleven are fixed. THE RESIDUE IS NOT THIS PATTERN and is split out as bug-p-sizeof-of-a-type-name-is-settled-against-a-kind-that-cannot-express-the-size [umbrella-sizeof-is-one-answer]: ShortString plus PChar/PAnsiChar/PWideChar/TextFile (four this ticket never recorded) accept `var v: N` and reject `SizeOf(N)`, and no ordering fix reaches them because 582e4de09's fallback is TypeSize(KIND) and no kind carries 263 or 4128. Ordering was necessary and not sufficient, as this ticket said from the start -- it just turned out the insufficiency was a sizing-model question rather than a parse-order one."
---

# `SizeOf(N)` rejects twelve builtin type names that `var v: N` accepts

## The census — all 51 builtin names, measured

For each name: compile `var v: N; WriteLn(SizeOf(v))` and `WriteLn(SizeOf(N))`.
Thirteen disagree; the other 38 agree exactly.

| name | `SizeOf(v)` | `SizeOf(N)` |
| --- | ---: | ---: |
| SizeUInt, ValReal, TDateTime, Currency | 8 | **rejected** |
| LongBool | 4 | **rejected** |
| WordBool | 2 | **rejected** |
| ByteBool | 1 | **rejected** |
| Comp, OleVariant | 8 / 16 | **rejected** |
| UTF8String, RawByteString, ShortString | 8 | **rejected** |
| Extended | 8 | **10** |

The error is `SizeOf: unknown type or variable`, with nothing hinting the type
itself is fine — the same no-diagnostic shape `BuiltinTypeNameTk`'s header says
it was created to end.

`Extended` is **not** part of this ticket: it needs a ruling on what `Extended`
IS, not a lookup, and it already has one —
[[bug-p-sizeof-extended-disagrees-with-the-storage-extended-gets]] [P p65].

This is the FOURTH ticket from one two-table split, after
[[bug-a-sizeof-real-disagrees-with-the-storage-real-actually-gets]], the
`Extended` one, and
[[bug-p-sizeof-string-disagrees-with-the-storage-string-actually-gets]].

## The obvious fix is wrong — built, measured, reverted

`BuiltinTypeNameTk` ends in `else Result := tyUnknown`. Chaining the declaration
path there (`else Result := BuiltinScalarTypeKind(nm)`) fixes twelve of the
thirteen in one line, keeps the fixedpoint, and passes the whole census. **It is
still wrong**, and the safety argument for it — *"every arm above still wins, so
this can only turn a REJECTION into an answer"* — is false:

```pascal
type Currency = record a, b, c: Integer; end;   { a USER type }
var longbool: Boolean; tdatetime: array[0..9] of Byte;
```

| | correct (pinned) | with the chain |
| --- | ---: | ---: |
| `SizeOf(Currency)` — the user's record | 12 | **8** |
| `SizeOf(longbool)` — a `Boolean` variable | 1 | **4** |
| `SizeOf(tdatetime)` — a 10-byte array | 10 | **8** |

`SizeOf`'s dispatch consults `BuiltinTypeNameTk` **first** and only reaches the
record/alias/array tables in its `else`. So a rejection there was never a
rejection — **it was the fallthrough into the user-type lookup**, which is
exactly what the table's own header warns about: *"Callers must consult a user
type alias FIRST where that matters: this answers what the name means as a
BUILTIN, not what the current scope binds it to."* SizeOf is a caller for which
it matters, and does not.

**Why the census could not see this**: every probe program declared no user
types, so `rejected` and `resolved by the user-type path` produce identical
output. The measurement was correct and answered a different question — a
negative result with two indistinguishable causes, and only the one I was
looking for in view.

## The real fix

Reorder `SizeOf`'s dispatch so the user tables (record, class, array alias,
type alias, enum) are consulted **before** `BuiltinTypeNameTk`, matching what
that header already tells callers to do; *then* the chain above is safe and
closes twelve rows. Note the reorder is a behaviour change in its own right —
today a user `type Integer = ...` loses to the builtin — so it wants its own
before/after census, with the shadowing program above as the positive control.

Possibly the same job as
[[refactor-p-five-dispatch-sites-for-one-named-type-cast]].

## Reproducing the census

Loop the 51 names, compiling the two one-line programs above for each, and diff
the columns. Roughly 100 sub-second compiles. **Include at least one user type
whose name collides with a builtin** — without that the run cannot distinguish
the two causes, and will report a clean fix for the change that regressed.


## Census RE-MEASURED 2026-09-02 (frankC), and the old one had gone stale

The summary previously said "the twelve REJECTED names it opened on are fixed".
Eleven are. Measured on a build at `a2d79bd42a1c`, and on the **pinned** binary
`766b99f98` (v401), which POSTDATES `582e4de09` and so is a valid control:

| name | `var v: N` | `SizeOf(N)` |
| --- | --- | --- |
| SizeUInt, ValReal, TDateTime, Currency, LongBool, WordBool, ByteBool, Comp, OleVariant, UTF8String, RawByteString | accepted | **fixed, agrees** |
| ShortString | accepted, 263 | **still rejected** |
| PChar, PAnsiChar, PWideChar | accepted, 8 | **rejected — not previously recorded** |
| TextFile | accepted, 4128 | **rejected — not previously recorded** |

Identical on the pinned binary, so none of it is a regression from the
`ParseTypeKind` work; the four extra names are simply not in this ticket's
original table, which enumerates only the thirteen it found.

`SizeOf: unknown type or variable` in every failing case — the same
no-diagnostic shape `BuiltinTypeNameTk`'s header says it was created to end.

## Why the five that remain are NOT another ordering fix

`582e4de09` added a fallback for exactly this — a name demoted from builtin and
then unresolved must come back to the builtin answer — and wrote
`prevTok := TypeSize(szBTkAny)`. **That fallback cannot answer for these five**,
because it takes a KIND. `ShortString` is 263 bytes and `TextFile` is 4128; no
`TTypeKind` carries a capacity or a record layout, so there is no value
`szBTkAny` could hold that would produce them. The declaration side gets all
five right precisely because it resolves a TYPE rather than looking up a kind.

That is `umbrella-sizeof-is-one-answer` shape 1 in one sentence, on this
ticket's own residue. The fix direction is for `SizeOf(name)` to resolve the
name through the declaration machinery, not to add a table entry — adding one
would be the fifth oracle the umbrella exists to prevent.

**Both known INSTANCES of the pattern are closed**; what is left is this
sizing-model question. Whoever takes it should decide whether this ticket is
still the right home or whether the residue belongs directly under the umbrella.

### Corroborated independently, with an instrument that fails differently (frankB)

Measured the same five names the same day without having seen the above, at
`a979184e2972`, and got the identical values — so this is corroboration rather
than one reading repeated. The instruments differ where it matters: the table
above reads `SizeOf(v)` of a VARIABLE, which is the operator under repair, so I
took the values off the physical element STRIDE of an array instead
(`@a[1] - @a[0]`). `ShortString` 263 and `TextFile` 4128 are real storage, not
just what `SizeOf` claims about it.

**Do not "fix" these toward fpc's numbers**, which the table above does not
list and which are the obvious wrong target: fpc says 256 for `ShortString`
(1-byte prefix, where ours is a 255-cap `tyFixedString` with an 8-byte length
word) and 888 for `TextFile` (a smaller `Text` record). Ours are 263 and 4128
and they are correct about our own storage. That is the same distinction
be76fab5a turned on.

`SizeOf(ShortString)` = 263 now falls out of `SizeOfSlot(tk, cap)` for free:
`SizeOfSlot(tyFixedString, DEFAULT_STR_CAP)` is exactly 263. So the carrier the
fix needs already exists for the string case; what is missing is that the NAME
never reaches a sizing call.

Where the declaration arms live, for whoever factors the resolver:
`pasparser_decl.inc:506` (textfile, and it needs `IsRecordType('text')`),
`:519` (shortstring, sets `LastTypeStrCap`), `:636` (pchar/pansichar). Each sets
something a kind cannot carry, which is why `BuiltinTypeNameTk`'s header states
the rule that only side-effect-free names live in the shared table — these five
are precisely the names that break it, and `TextFile` proves a width table alone
would not be enough.


## Closed 2026-09-02 — both instances fixed, residue split out

The second instance (`ParseTypeKind`) is fixed in `2ba37ba91`. Eleven of the
twelve names are resolved.

**The five that remain are a different defect and now have their own slug**,
[[bug-p-sizeof-of-a-type-name-is-settled-against-a-kind-that-cannot-express-the-size]],
wired under [[umbrella-sizeof-is-one-answer]] at the coordinator's routing call.
Split rather than left here because a ticket titled "twelve type names" whose
twelve names are resolved reads as done, and CLAUDE.md is explicit that the
summary is the only part everyone reads — leaving a live sizing-model question
as residue on a closed-looking ticket is how it gets skipped.

**This ticket's own census had gone stale before that split**, which is worth
keeping visible: it recorded all twelve as fixed when eleven were, and did not
list four names in the same family at all. Re-measured against the pinned binary
`766b99f98`, which postdates `582e4de09` and is therefore a valid control, and
corroborated by frankb-a9 through array STRIDE rather than `SizeOf` — a second
instrument chosen precisely because `SizeOf` is the operator under repair.

The header's own warning held all the way through: *ordering is necessary and
not sufficient*. What it could not have known is that the insufficiency was not
a parse-order problem at all.

## Log
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
