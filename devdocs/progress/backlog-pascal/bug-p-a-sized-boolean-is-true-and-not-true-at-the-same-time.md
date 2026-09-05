---
track: P
prio: 55
type: bug
blocked-by: []
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
