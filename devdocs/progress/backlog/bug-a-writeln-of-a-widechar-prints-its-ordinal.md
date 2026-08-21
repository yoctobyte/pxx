---
track: A
prio: 40
type: bug
blocked-by: []
summary: "WriteLn(w) where w: WideChar prints the NUMBER (65 for 'A') instead of the character, because WideChar has no type kind of its own — it collapses to tyUInt16, so WriteLn cannot tell it from a Word. UCS4Char has its own kind (tyUCS4Char) for exactly this reason; WideChar should get the same. Found by a WideChar-source x string-context differential against FPC 3.2.2."
---

# `WriteLn` of a WideChar prints its ordinal, not the character

- **Type:** bug (silent wrong OUTPUT, no diagnostic) — Track A (the type kind is
  core; the conversion sites are the Pascal frontend)
- **Status:** backlog
- **Opened:** 2026-08-21, from the differential run in
  [[refactor-centralize-managed-string-pchar-conversion]]

## Measured

Six WideChar sources × five string contexts, each program diffed against
fpc 3.2.2. Every context CONVERTS correctly except `WriteLn`:

```pascal
var w: WideChar;
begin
  w := 'A';
  s := w;        WriteLn(Length(s), ' ', s);   { both: 1 A     }
  s := 'x' + w;  WriteLn(s);                   { both: xA      }
  Show(w);                                     { both: A       }
  WriteLn(w);                                  { FPC: A   pxx: 65 }
end.
```

Same for a record field, an array element, a function result and a
`WideChar(n)` cast — the `writeln` row is the only one that diverges, and it
diverges for ASCII too, so it is not the encoding question below.

## Why

`WideChar` collapses to **`tyUInt16` with no marker**
(`pasparser_lval.inc:4636`: `NodeIsWideCharVal` recognises only the CAST node,
`AN_PTR_CAST` with the `-3` sentinel). The assign/concat/argument paths work
around that by ALSO accepting "any tyUInt16 flowing into a string context",
which is safe there because a bare `Word` in a string context is meaningless
anyway.

`WriteLn` cannot use that trick: `WriteLn(someWord)` must print the number, and
`WriteLn(someWideChar)` must print the character, and by the time the argument
is lowered the two are the same type. So this is not a missing call to an
existing helper — it is missing INFORMATION.

## The fix, and the precedent that settles it

**`UCS4Char` already has its own kind, `tyUCS4Char`**, added for exactly this
reason: `WrapUCS4ToUTF8`'s comment says the kind is what makes the conversion
decidable, "storage is tyUInt32's". WideChar is the same problem one width
down and should get `tyWideChar` the same way:

1. a `tyWideChar` kind whose storage is `tyUInt16`'s,
2. `var w: WideChar` declares it, `WideChar(x)` casts to it,
3. the existing "any tyUInt16 in a string context" fallbacks then narrow to it
   (they can stay as a fallback — additive, per this ticket family's rule),
4. `WriteLn` gains the one arm it cannot have today.

Not attempted in the session that found it: a new type kind touches the shared
`defs.inc` numbering, and the finding is worth more written down than half
applied.

## NOT part of this ticket: the encoding divergence

The same differential shows `s := w` for a NON-ASCII code unit giving 2 bytes
under pxx and 1 under FPC — pxx encodes UTF-8 (`__pxxWideCharToUTF8`), FPC
converts through the system codepage. That is a deliberate dialect choice, it
is consistent across every conversion site, and it is not a defect. It belongs
in user-facing docs (Track D) rather than in a bug ticket; noting it here so
the next reader of that diff does not re-file it.

## Gate

Track A's: `make compiler/pascal26` (byte-identical fixedpoint) +
`tools/gate.sh quick`, plus a `WriteLn(w)` row against FPC's output.
