---
slug: bug-p-not-over-a-longbool-inverts-the-branch-because-the-sized-booleans-are-integers
track: P
type: bug
prio: 60
status: backlog
created: 2026-09-06
found-by: frankB
owner: ""
blocked-by: []
title: "`if not lb then` takes the wrong branch for a LongBool — the sized booleans are integer kinds wearing a boolean name"
summary: "`ByteBool`/`WordBool`/`LongBool` resolve to `tyUInt8`/`tyUInt16`/`tyInteger` in BuiltinScalarTypeKind, so they are integers and the boolean OPERATORS are bitwise. `not lb` for a True LongBool is -2, which is nonzero and therefore reads as TRUE: `if not lb then` TAKES THE BRANCH IT MUST SKIP, silently, no diagnostic. Measured against fpc 3.2.2 on identical source. `WriteLn(lb)` prints 1/0 where fpc prints TRUE/FALSE, and `lb and b` is bitwise. THE ABI HALF IS ALREADY CORRECT and was checked before ranking: any nonzero reads TRUE and zero reads FALSE, byte-identical to fpc, so this is broken at the operators and not at the interop boundary. The mapping's own comment is TRUE and is why the fix is not `Result := tyBoolean`: these must keep their WIDTH or every struct crossing to C resizes. A sized boolean carries TWO facts -- boolean-ness and a width -- and the kind slot holds one, so the author kept the fact their bug was about. Note the fix may need new TTypeKind ordinals, which defs.inc says to coordinate with Track A before touching."
---

# `not` over a sized boolean inverts the branch

Measured 2026-09-06 at commit `d3fe44947`, compiler `827722c842de`, against
fpc 3.2.2, same source file both ways.

```pascal
var lb: LongBool;
begin
  lb := True;
  if not lb then WriteLn('taken') else WriteLn('skipped');
end.
```

```
pxx  -> taken     WRONG
fpc  -> skipped   right
```

`not lb` evaluates to **-2**: a bitwise complement of 1. -2 is nonzero, and
nonzero reads as TRUE, so the negation of TRUE is TRUE.

Only the `True` side is wrong. `lb := False; if not lb` is correct in both, so
a test that exercises the false case alone passes.

## The rest of the family goes with it

| | pxx | fpc |
| --- | --- | --- |
| `WriteLn(bb)` for `bb: ByteBool := True` | `1` | `TRUE` |
| `WriteLn(wb)` for `wb: WordBool := False` | `0` | `FALSE` |
| `WriteLn(not lb)` | `-2` | `FALSE` |
| `WriteLn(lb and b)` | `1` | `TRUE` |
| `Ord(True)` for any `*Bool` | `1` | `-1` |

## What is NOT broken, checked before ranking this

The interop semantic is already right, and it is the one that matters at the
ABI boundary:

```
LongBool holding 2   -> reads TRUE  in both
LongBool holding 256 -> reads TRUE  in both
LongBool holding 0   -> reads FALSE in both
```

So this is broken at the OPERATORS, not at the boundary the type exists for.
That is also why it has survived: code that only ever tests a `*Bool` returned
from C, without negating it, works perfectly.

## Cause, and why the obvious fix is wrong

`BuiltinScalarTypeKind` in `pasparser_lval.inc`:

```pascal
else if CaseEqual(nm, 'longbool') then Result := tyInteger
else if CaseEqual(nm, 'wordbool') then Result := tyUInt16
else if CaseEqual(nm, 'bytebool') then Result := tyUInt8
```

Its comment is correct about its own case and should be read before changing
anything: *"FPC's sized booleans are C-ABI booleans — a fixed-width integer
where nonzero means true. They must keep their WIDTH (LongBool 4, WordBool 2,
ByteBool 1); mapping them onto tyBoolean would silently resize any struct or
call that crosses to C."*

**So `Result := tyBoolean` is not the fix** — it trades a wrong branch for a
wrong layout, which is worse because a layout bug crosses to C.

**A sized boolean carries two facts — it is a boolean, and it is N bytes wide
— and the kind slot holds one.** The author had a width bug in front of them,
kept the width, and the boolean-ness was discarded silently. This is the same
shape as `SizeOfSlot(tk, cap)` in Group 19, and as `VariantBoxToTemp` before
it: one slot, two questions.

## Two shapes for the fix, and the choice is not mine alone

1. **New kinds** — `tyBool16` / `tyBool32` / `tyBool64` beside the existing
   `tyBool8` (defs.inc ordinal 29). Clean, and it is exactly the enumeration
   widening that `CLAUDE.md` says to coordinate with Track A by message before
   touching, because it moves TTypeKind ordinals.
2. **A separate carrier** — keep the integer kind and record boolean-ness
   beside it, the `VariantBoxToTemp` remedy for one-slot-two-questions. No
   ordinal churn; more sites to teach.

Whoever takes this should say which, out loud, before writing it.

## Neighbours found in the same measurement

`Boolean16`, `Boolean32`, `Boolean64` and `QWordBool` are refused outright
(fpc: 2, 4, 8, 8 bytes). `Boolean16` is a real corpus wall: `uthlp.pp` needs
it and twelve `tthlp*` test files use that unit. Those are a FEATURE gap and
belong with this one because they land in the same table — but note the order
in which they announce themselves: **the missing names produce an error message
and the wrong branch does not.** Adding the four names without fixing this one
would move the corpus wall forward and look like progress.
