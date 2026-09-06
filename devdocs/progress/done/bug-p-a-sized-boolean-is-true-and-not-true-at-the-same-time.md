---
track: P
prio: 70
type: bug
blocked-by: [decide-how-a-type-carries-an-identity-its-kind-cannot-hold]
summary: "FIXED 2026-09-06 (71b5bac58, vehicle ef518700b) -- and the aperture was WIDER than reported: `and`, `or` and all six comparisons were wrong too, on a nonzero-not-one value, which no probe here used. `not` is now normalised to `x <> 0` rather than re-tagged, because the logical path lowers to `xor 1` and $C8 xor 1 is still true. `xor` is left BITWISE, matching fpc, measured. Was: `var a: ByteBool; a := True;` makes BOTH `if a` and `if not a` fire -- a program takes both branches, silently, no diagnostic. `not` on a sized boolean is an INTEGER complement: not 1 = 254, nonzero, true. It is right for False only by accident (not 0 = 255, also true, which is the wanted answer). WordBool and LongBool identical; plain Boolean is correct. Cause: ByteBool/WordBool/LongBool are mapped to tyUInt8/tyUInt16/tyInteger to keep their C-ABI WIDTH -- deliberate and documented -- so nothing downstream can tell them from integers. Same cause drops their display (WriteLn prints 1, fpc prints TRUE) and their Ord (1 here, -1 in fpc, all-bits-set being the C convention). QWordBool does not exist at all. Pre-existing on pin v403. Fixing it needs a way to say \"integer kind, boolean semantics\", which is a defs.inc design fork, not a local patch.
status: done
---

# A sized boolean is true and not-true at the same time

> **ORDERING HAZARD — READ THIS BEFORE DOING EITHER TICKET.** Every spelling
> `Boolean16` can have TODAY is already a defect: `tyUInt16` gets the width
> right and `not` / `WriteLn` / `Ord` wrong; `tyBoolean` gets those right and
> the width wrong (`defs.inc` has exactly two boolean kinds, `tyBoolean` and
> `tyBool8`, and both are ONE BYTE). So adding the four names moves the corpus
> wall forward while shipping four more instances of the sibling bug — it looks
> like progress and it is not. That converts
> `decide-how-a-type-carries-an-identity-its-kind-cannot-hold` from an argument
> to have before this work into a SCHEDULE for it: the fork is not optional
> here, it is the ordering constraint.


```pascal
var a: ByteBool;
a := True;
if a then Write('then ');          { fires — correct }
if not a then Write('not-then ');  { ALSO FIRES }
```

Measured 2026-09-05, HEAD and pin v403 identically; fpc 3.2.2 prints `then`
only.

```
                 pxx                     fpc
ByteBool True    then not-then           then
ByteBool False   not-then                not-then
Boolean  True    then                    then
```

**`not a` is always true for a sized boolean.** The value is an integer, so
`not` is a bitwise complement: `not 1` is 254 and `not 0` is 255, both nonzero,
both read as true. The False row is right BY ACCIDENT — which is why this
survives casual testing, and why a probe that only sets False cannot see it.

Comparisons are unaffected: `a = True` and `a <> False` both answer correctly,
so the bug is specific to the `not` lowering rather than to the type's truth
test.

## Cause, and why it is not a local patch

`pasparser_lval.inc` maps the sized booleans onto integer kinds ON PURPOSE, and
says so:

> *"FPC's sized booleans are C-ABI booleans — a fixed-width integer where
> nonzero means true. They must keep their WIDTH (LongBool 4, WordBool 2,
> ByteBool 1); mapping them onto tyBoolean would silently resize any struct or
> call that crosses to C."*

That reasoning is right and the width IS right (1/2/4, matching fpc). What the
comment weighed was two options — map to `tyBoolean` and lose the width, or map
to an integer and keep it. There is a third: **keep the integer kind for layout
and record the boolean-ness beside it**, the way an enum is `tyInteger` plus an
id rather than a kind of its own. Nothing in the tree can currently express
that for these types, so `not`, `WriteLn` and `Ord` all see a plain integer.

Three symptoms, one cause:

| | pxx | fpc |
|---|---|---|
| `not a` when a is True | true | false |
| `WriteLn(a)` | `1` | `TRUE` |
| `Ord(a)` when True | `1` | `-1` (all bits set) |

`Ord` is the C convention rather than a quirk, and it is the tell that these are
ABI types: a value that crosses to C must be all-bits-set, not 1.

**QWordBool does not exist at all** — `unknown type: QWordBool`, where fpc gives
it 8 bytes. It is deliberately NOT being added first: adding a fourth member to
a family whose `not` is broken is not progress, and it would inherit every row
above.

## The fork this needs settling first

Adding a distinct kind trio (tyByteBool/tyWordBool/tyLongBool) touches
`TTypeKind` in defs.inc, which CLAUDE.md names as the one thing to coordinate by
message rather than just edit. The alternative — a side channel like the enum
id, carried through symbols, record fields, params and the alias table — is the
same shape as
[[bug-p-a-type-alias-drops-the-enum-identity-and-a-set-drops-its-char-element-kind]]
and would fix both families at once. Pick one before writing code.

## Why prio 55

Higher than the display and identity bugs beside it because this one makes a
compiling program take BOTH branches of a conditional with no diagnostic, and
the affected types are exactly the ones an FPC binding to a C library declares.
A wrong answer that announces itself is cheaper than this.

## Found by

Chasing `tenum6.pp`, whose skip reason reads *"gap: `Str()` of boolean /
ByteBool / WordBool / LongBool / QWordBool ('FALSE')"*. `Str(True:0, s)` works
fine here — the reason is a symptom label again, and the mechanism underneath it
is nothing to do with `Str`.

## The fork is filed

[[decide-how-a-type-carries-an-identity-its-kind-cannot-hold]] (Track U, p55)
carries the two options, the trade-offs and a recommendation. Do not start here
— the choice made there decides how this is fixed, and picking wrong makes the
enum-identity family wider rather than merely later.

## Re-measured 2026-09-06 — frankB (commit `d3fe44947`, compiler `827722c842de`, fpc 3.2.2)

Independently reproduced, still live. I filed a duplicate of this ticket before
finding it and retracted it in the same commit; everything in it except the
`BooleanNN` names was already here, and this ticket's diagnosis was better —
it names the defs.inc fork, mine only named the mapping.

**But the NUMBER is not a duplicate — it is a second instrument, and the pair
is the finding** (frank-coordinator's catch). This ticket measured `ByteBool`
and got `not 1` = **254**: unsigned, one byte, via `tyUInt8`. I measured
`LongBool` and got `not lb` = **-2**: signed, four bytes, via `tyInteger`.
**Same defect, and the two land nonzero for different arithmetic reasons.**
Neither reading could have gone wrong the way the other did, which is what
makes them corroboration rather than repetition — and it is what shows the
defect is the MAPPING and not one type's arithmetic. Keep both numbers.

Re-ranked 55 -> 70 on this justification: it is a silent control-flow
inversion in the one type family that exists specifically for C and Win32
interop — i.e. exactly where real source writes `if not SomeApiCall(...) then`.
The prio predated the `if not lb then / else` spelling, which states the harm
more plainly than "both branches fire".

The `else` arm makes the same defect read as a plain inversion rather than as
a double fire, which may be the more recognisable spelling for whoever fixes it:

```pascal
lb := True;
if not lb then WriteLn('taken') else WriteLn('skipped');
  pxx  -> taken     fpc -> skipped
```

`not lb` for a LongBool is **-2** (`not 1` at 32 bits), so it is nonzero and
therefore true.

### A control that passes under this bug, recorded because I used it

I checked "does any nonzero read as TRUE" first and got a clean match with fpc
— 2 reads TRUE, 256 reads TRUE, 0 reads FALSE — and concluded from it that the
divergence was confined to the value STORED by `a := True`. **That control is
on the arm that works.** It exercises `if a`; the defect is in `if not a`. It
passes under the bug and it certified the wrong conclusion, which would have
downgraded this to a display-and-Ord difference.

Consequence for anyone triaging: **this cannot go to `known-incompat/`.** That
folder is for two behaviours each correct about their own implementation, and a
type where `a` and `not a` are simultaneously true is not correct about
anything. The `Ord(True)` = 1-vs--1 row is not a chosen representational
difference either — it is one visible face of the mapping that also makes `not`
wrong, so it resolves with this and needs no separate "does real source mean
it" analysis.

### And an ordering hazard, from how I got here

`Boolean16`/`Boolean32`/`Boolean64` are missing entirely (fpc: 2, 4, 8 bytes)
and are filed separately as a feature gap —
`feature-p-the-booleannn-family-of-explicit-width-boolean-type-names`. That
gap is a real corpus wall: `uthlp.pp` needs `Boolean16` and twelve `tthlp*`
files use that unit.

**Fix the names first and the corpus moves one wall forward while this stays
in.** A missing name produces an error message and a wrong branch does not, so
the feature gap is the one that recruits an owner. Whoever picks up the
`BooleanNN` ticket should read this one first — they land in the same table.

## 2026-09-06 (frankA) — a FOURTH face, and this one is asymmetric between two spellings

The summary lists three consequences of one cause: `not` complements an integer,
`WriteLn` prints a digit, `Ord` answers 1 instead of -1. There is a fourth, and
unlike the other three it depends on how the type is SPELLED:

    High(ByteBool)               -> REFUSED
    type b = ByteBool; High(b)   -> 255      (WordBool 65535, LongBool 2147483647)
    fpc 3.2.2, both spellings    -> TRUE

**The refusal is a mitigation and the one-line alias routes around it.**
`bug-p-thirteen-builtin-type-names-answer-at-some-doors-and-are-refused-at-others`
records that the direct door refuses on purpose — answering `High` from the kind
would give an ordinal — so that door is declining a question it cannot answer
correctly, and the alias door has no such scruple. A refusal is loud and a wrong
bound is silent.

It matters for THIS ticket because it changes what the fork is exclusively
required for. Making `High` answer `TRUE` needs the identity carrier, same as the
other three faces. Making the two spellings AGREE does not: the alias path can
refuse exactly as the direct path does, today, independently of how
`decide-how-a-type-carries-an-identity-its-kind-cannot-hold` is settled. So there
is a defensible interim state that is strictly smaller than the fork, and it was
invisible until someone asked the second spelling.

Found by sweeping all 51 names from the union of `OrdinalNameToTk` and
`BuiltinScalarTypeKind` in both spellings; these three are the only cell in that
sweep where the spelling changes the answer. Detail and the negative half — zero
direct-vs-alias disagreements at `SizeOf`, `High`/`Low` and `TypeInfo` for every
other name — are on the thirteen-names ticket.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit a3532e1f8.

## Fixed 2026-09-06 (frankH) — and the aperture was wider than this ticket

`71b5bac58`, with the identity vehicle in `ef518700b`. Arm B of
[[decide-how-a-type-carries-an-identity-its-kind-cannot-hold]], as decided.

**`not` is normalised, not re-tagged, and the difference is the whole fix.** The
first attempt set `bitNot := False` and let the logical path have the operand as
it stood. **That path lowers to `xor 1`** — correct for a canonical 0/1 Boolean
and wrong for a C-ABI one: `ByteBool(200)` is `$C8`, `$C8 xor 1` is `$C9`, still
nonzero, still true. So the operand is converted to an ordinary `x <> 0` once,
at the top of the expression parser, and `not` learns nothing.

**Caught only because the test carries a nonzero-but-not-one row.** Every row in
this ticket used 0 and 1, and on those inputs the broken fix and the correct one
agree exactly.

### THIS TICKET'S "COMPARISONS ARE UNAFFECTED" WAS TRUE OF THE VALUES AND FALSE OF THE TYPE

Same cause, and no ticket had it, for the same reason. With
`a := ByteBool(200)` and `b := ByteBool(1)`, both true, against fpc 3.2.2:

| | was | fpc |
| --- | --- | --- |
| `a and b` | 0 (bitwise `200 and 1`) | TRUE |
| `a or b` | -55 | TRUE |
| `a = b` | FALSE (raw ordinals) | TRUE |

`and`, `or` and all six comparisons now normalise both operands when at least
one side is a sized boolean and both sides are truth values — never when the
other side is an integer, so `a and 3` stays a type error to be diagnosed
rather than being quietly rewritten into something that compiles.

**`xor` is deliberately left BITWISE** and that is measured: fpc answers
`Ord(a xor b)` = -55 while `Ord(a and b)` = 1. Bit patterns are meaningful in
the type family that exists for the C ABI. Its result keeps the sized-boolean
identity, so `WriteLn(a xor b)` prints TRUE while `Ord` of the same expression
is the pattern.

**The ORDINAL of a logical result is not asserted anywhere and must not be.**
fpc's own answer moves with the SHAPE of the operands — 1 for two variables,
-56 (the left operand's own bits) when the right side is written `ByteBool(1)`.
There is no ordinal there to be compatible with; the declared type's value is
the claim.

### The `Ord` and display rows resolved with it, as this ticket predicted

`Ord` needed **two** independent fixes and this ticket's diagnosis named only
one of them. `tyInt8`/`tyInt16` (signedness) fixes `Ord(ByteBool(255))` = -1;
materialising `True` as all-bits-set fixes `Ord(b)` after `b := True`.
**LongBool was already signed and still answered 1**, which is the control that
separates them.

`QWordBool` is still not a type name — untouched, and it inherits none of the
above now rather than all of it.

### Tests

`test_a_sized_boolean_is_not_true_and_not_true_at_once` (this ticket) and
`test_a_sized_boolean_is_a_boolean_at_every_renderer`, both byte-identical to
fpc 3.2.2's own output, both wired into the Makefile. The False rows are marked
in the source as the ones that **cannot** fail.
