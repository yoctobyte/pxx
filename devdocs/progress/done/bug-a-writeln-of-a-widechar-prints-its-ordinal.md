---
track: A
prio: 40
type: bug
blocked-by: []
summary: "FIXED 2026-08-22 with tyWideChar, kind 31. WriteLn(w) where w: WideChar printed the NUMBER (65 for 'A') instead of the character, because WideChar has no type kind of its own — it collapses to tyUInt16, so WriteLn cannot tell it from a Word. UCS4Char has its own kind (tyUCS4Char) for exactly this reason; WideChar should get the same. Found by a WideChar-source x string-context differential against FPC 3.2.2."
---

# `WriteLn` of a WideChar prints its ordinal, not the character

- **Type:** bug (silent wrong OUTPUT, no diagnostic) — Track A (the type kind is
  core; the conversion sites are the Pascal frontend)
- **Status:** done
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

## Fixed — 2026-08-22

Exactly the four steps this ticket proposed, and the precedent held all the way:

1. **`tyWideChar`, kind 31** in `defs.inc`, appended at the tail so no ordinal
   shifts. `TypeSize` 31 → 2, `TypeIsOrdinal` 31 → True; unsigned, so
   `TypeSigned` needs nothing.
2. **`var w: WideChar` declares it** — `pasparser_decl.inc`'s name table and
   `OrdinalNameToTk` both now answer `tyWideChar` where they answered
   `tyUInt16`. The `WideChar(x)` CAST needed no edit at all: that site already
   does `ASTTk[node] := Ord(OrdinalNameToTk(name))`, so it picked the kind up
   for free, and its `-3` marker still rides along.
3. **`NodeIsWideCharVal` answers on either evidence** — the `-3` cast marker
   (all a cast leaves) or `ASTTk = tyWideChar` (what survives a variable). The
   `...or the operand is tyUInt16` clauses beside its call sites were LEFT IN
   PLACE: additive, per this ticket family's rule, and retiring them is its own
   migration.
4. **`WriteLn` gained the arm it could not have**, in the same two-place shape
   the char-array wrap beside it already uses — rewrite `ASTLeft[item]` for the
   `AN_ARG` / `AN_PAIR` forms (rewriting `item` would break the argument chain
   in `ASTRight[item]`), and a bare branch in the dispatch below.

### Measured, before and after

63 programs, WideChar source shape × context, each diffed against fpc 3.2.2.
**29 ok before → 38 after, with ZERO regressions.** The nine are every writeln
shape: bare variable, cast, record field, array element, function result, two
in one call, interleaved with literals, and `Write` + bare `WriteLn`.

The regression half mattered more than the fix half, because a new type kind is
exactly the change that quietly costs a type its ordinal-ness — 68 sites name
`tyUInt16` and most are `in [...]` sets that kind 31 is not a member of. None of
them turned out to be load-bearing here: comparisons, `Ord`, `Inc`/`Dec`,
`Succ`/`Pred`, `case`, `for`, array indexing, `var`/`const` parameters, record
fields, `SizeOf` and every string context all still agree with FPC. That is the
same result `tyUCS4Char` got, and for the same reason — everything that cares
about SIZE or ordinal-ness routes through `TypeSize` / `TypeIsOrdinal`, which is
why registering the kind in those two functions is the whole cost.

### What did NOT become identical, and why that is still progress

The 25 remaining diffs are all the **non-ASCII encoding divergence** this ticket
already excluded: pxx encodes a WideChar as UTF-8, FPC converts through the
system codepage, so `WideChar(233)` is two bytes here and one there. `WriteLn`
used to be the one context that dodged this by printing `233` instead —
now it prints the UTF-8 é like every other conversion site in pxx does. So the
writeln row moved from *wrong* to *consistently divergent*, which is the
dialect's documented position
(`devdocs/dev/pascal-dialect-divergences.md`), not a defect.

### Test

`test/test_widechar_writeln_prints_the_character.pas`, wired into `test-core`.
Two halves on purpose: the eight writeln shapes, then the ordinal battery that
the new kind could have broken. **Byte-identical to fpc 3.2.2.** ASCII only —
a non-ASCII row would encode the divergence above into a test and make the
oracle useless.

### Gate

`make compiler/pascal26` (byte-identical fixedpoint, converged in 1 round) +
`tools/gate.sh quick`.

## Log
- 2026-08-22 — resolved, commit PENDING-COMMIT.
