---
slug: bug-a-for-in-over-a-set-variable-refuses-the-kinds-its-error-message-claims
track: A
prio: 50
status: done
commit: PENDING-COMMIT
---

# `for x in <named set type>` is refused — by an error naming the kinds it refuses

```pascal
type TS = set of Char;
var cs: TS; c: Char;
...
for c in cs do Write(c);
```

```
error: for-in: set iteration supports `set of <enum>`, `set of Char` or an
       ordinal set constructor
```

The message lists `set of Char` as supported and then refuses a `set of Char`.
Same for `TB = set of 0..7` and `set of Byte`. Found while sweeping `Continue`
coverage for `bug-a-continue-in-a-for-in-loop-never-advances` — two rows of that
sweep could not even be compiled, which is how this surfaced.

## What actually decided it — the alias, not the loop

The desugar was never the problem. `BuildForInSetLoop` handles
`setElemTk = Ord(tyChar)` and every ordinal element kind; it reaches the `Error`
only when the element kind it is handed is *nothing* (0).

The split is **named vs inline**, and it is exact:

| declaration | works |
| --- | --- |
| `var cs: set of Char;` | yes |
| `type TS = set of Char; var cs: TS;` | **no** |
| `type TES = set of TE; var es: TES;` (enum) | yes |
| bare `for i in [5,1,3]` constructor | yes |

The enum alias worked and the others did not, because the alias table stored
**only the element ENUM id**:

```pascal
propEnumId := FindEnumType(CurTok.SVal);
RegisterSetAlias(tnOff, tnLen, propEnumId);
while not (CurTok.Kind in [tkSemicolon,tkEOF]) do Next;   { throw the rest away }
```

For `set of TE` that id is everything you need. For `set of Char` and
`set of 0..7` `FindEnumType` returns -1 and the element type is then *skipped
over as text* — so `SymSetElemTk` came out 0 and the loop builder had nothing to
range over. `set of <enum>` was not "the supported case"; it was the only case
whose element identity happened to fit the one field the alias kept.

## The shape, again

This is `devdocs/dev/normalise-dont-special-case.md` for the sixth time this
session: **one concept, two parses.** `ParseTypeKind`'s inline arm parsed the
element properly — subrange via `ConstEval`, otherwise a full `ParseTypeKind` —
and recorded both halves (`LastTypeSetEnumId` + `LastTypeSetElemTk`). The
named-alias arm carried a reduced copy that recorded one half and skipped the
rest. **The second copy is the one that stayed broken.**

So the fix removes the copy rather than widening it:

- `ParseSetElemSpec` — the element parse, extracted from `ParseTypeKind`'s
  `set of` arm, setting both `LastTypeSet*` globals. Called from both sites.
- `AliasSetElemTk` — a real field for the element KIND next to `AliasElemTk`'s
  enum id, filled by `RegisterSetAlias` (now four params) and read back in
  `ParseTypeKind`'s named-set arm.

A dedicated field, not a reuse of `AliasPtrBaseTk`: overloading one slot per
alias flavour is what produced the missing half in the first place.

## Verification

`test/test_for_in_over_a_named_set_type.pas` — named set types over `Char`, an
integer subrange, an enum and `Byte`, plus `Continue` inside two of them. Six
lines, byte-identical to `fpc 3.2.2 -Mobjfpc -O1`:

```
ace / 136 / 02 / 9 200 / ae / 16
```

Timeout-guarded in the Makefile: the failure mode of a for-in bug in this family
is a spin, not a wrong line.

Gate: `make compiler/pascal26` (fixedpoint, converged after 1 round) +
`tools/gate.sh quick` GREEN.

## Note for whoever touches set RTTI next

`AliasElemTk` now means two different things depending on `AliasTk`: the pointee
kind for a pointer alias, the element ENUM id for a set alias. That predates this
ticket and this ticket did not fix it — it only stopped the set flavour from
silently losing its other half. If a third flavour ever wants that slot, split it
instead of adding a meaning.
