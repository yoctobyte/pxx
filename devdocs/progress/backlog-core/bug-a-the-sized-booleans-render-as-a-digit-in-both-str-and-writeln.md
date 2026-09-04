---
track: A
prio: 35
type: bug
status: backlog
owner: ""
created: 2026-09-04
blocked-by: []
summary: "`WordBool`, `LongBool` and `ByteBool` print as `1`/`0` from BOTH `writeln` and `Str`, where FPC (and our own `Boolean`) give TRUE/FALSE. Not the same defect as bug-p-str-of-a-boolean-formats-it-as-a-digit, which was one missing dispatch arm and is fixed: these three have no boolean-ness to dispatch ON. They are deliberately represented as integers of their own width (pasparser_lval.inc:6921 -- mapping them to tyBoolean would silently resize every struct that contains one), so both renderers correctly see an integer. The fix needs a way to carry `is a boolean` ALONGSIDE a width, which is a representation change, not a table row."
---

# The sized booleans render as a digit in both `Str` and `writeln`

Measured 2026-09-04 on x86-64, against `fpc 3.2.2 -Mdelphi -O1`, at
`c94252bb92cd`. Both renderers, one program:

| declared | `Str(x,s)` pxx | `writeln(x)` pxx | fpc, both |
| --- | --- | --- | --- |
| `Boolean`  | TRUE | TRUE | TRUE |
| `WordBool` | 1 | 1 | TRUE |
| `LongBool` | 1 | 1 | TRUE |
| `ByteBool` | 1 | 1 | TRUE |

The `Boolean` row is TRUE in that table because
`bug-p-str-of-a-boolean-formats-it-as-a-digit` was fixed in the same session;
before it, `Str` said `1` and `writeln` said TRUE.

## Why this is NOT that bug again

That one was a **missing dispatch arm**: `StrBool` existed, was correct, and
nothing routed to it. One line.

These three have nothing to route. `pasparser_lval.inc:6921` records the
decision and the reason: *"they must keep their WIDTH (LongBool 4, WordBool 2,
ByteBool 1); mapping them onto tyBoolean would silently resize any struct"*.
There is no `tyWordBool`/`tyLongBool`/`tyByteBool` — grep returns nothing — so
by the time either renderer sees the value it is an integer of width N and
**both are answering correctly about what they were given.** The information
was lost upstream, at the type, which is why fixing the renderers is the wrong
repair and would have to be done twice.

## What the fix actually needs

A way to say "boolean of width N" that survives to the renderer without
changing the storage width. That is a representation change in Track A's
territory, and whoever takes it should decide it once for `Str`, `write`,
`writeln`, `array of const` and `str()` in NilPy, rather than per renderer.
Doing it per renderer is exactly how `Str`'s dispatch table drifted from
`write`'s in the first place.

**A THIRD renderer already loses it, measured the same day** — so this is a
class and not two spellings. In `array of const`, `Boolean` boxes as
`vtBoolean` (tag 1) and `LongBool`/`WordBool` box as `vtInteger` (tag 0):

```
P([b, l, w]);   { b: Boolean, l: LongBool, w: WordBool }
vt1
vt0
vt0
```

Anything reading `VType` — `sysutils.Format`, a user `Log`, and phase 3 of
[[feature-writeln-as-library]] when it lands — therefore inherits the same
wrong answer for free, without a line of rendering code being involved. Fixing
the two statement renderers and stopping would leave that third one silently
wrong, which is the argument for repairing this at the type rather than at the
three call sites.

## Ranking

35, and the number is about **reach, not doubt** — the divergence itself is
certain and reproduces on one command. `LongBool` is what Windows-facing and
FFI-facing declarations use, so the population that hits this is real but is
not the core self-host corpus; nothing in `compiler.pas` renders one. Raise it
if a demo or an `examples/**` program prints one.

Repro (`fpc -Mdelphi -O1` disagrees on the last three rows):

```pascal
var s: ShortString; w: WordBool; l: LongBool; bb: ByteBool;
begin
  w := True;  Str(w, s); writeln('wordbool Str=', s, ' writeln=', w);
  l := True;  Str(l, s); writeln('longbool Str=', s, ' writeln=', l);
  bb := True; Str(bb, s); writeln('bytebool Str=', s, ' writeln=', bb);
end.
```
