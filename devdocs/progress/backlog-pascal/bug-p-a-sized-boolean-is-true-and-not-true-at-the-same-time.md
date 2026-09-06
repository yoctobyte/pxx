---
track: P
prio: 70
type: bug
blocked-by: [decide-how-a-type-carries-an-identity-its-kind-cannot-hold]
summary: "`var a: ByteBool; a := True;` makes BOTH `if a` and `if not a` fire -- a program takes both branches, silently, no diagnostic. `not` on a sized boolean is an INTEGER complement: not 1 = 254, nonzero, true. It is right for False only by accident (not 0 = 255, also true, which is the wanted answer). WordBool and LongBool identical; plain Boolean is correct. Cause: ByteBool/WordBool/LongBool are mapped to tyUInt8/tyUInt16/tyInteger to keep their C-ABI WIDTH -- deliberate and documented -- so nothing downstream can tell them from integers. Same cause drops their display (WriteLn prints 1, fpc prints TRUE) and their Ord (1 here, -1 in fpc, all-bits-set being the C convention). QWordBool does not exist at all. Pre-existing on pin v403. Fixing it needs a way to say \"integer kind, boolean semantics\", which is a defs.inc design fork, not a local patch."
---

# A sized boolean is true and not-true at the same time

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
