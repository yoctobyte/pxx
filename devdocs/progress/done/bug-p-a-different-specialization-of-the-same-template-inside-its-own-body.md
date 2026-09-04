---
slug: bug-p-a-different-specialization-of-the-same-template-inside-its-own-body
track: P
prio: 35
type: bug
blocked-by: []
status: done
created: 2026-08-30
summary: "FIXED 2026-09-04 for the non-swapped case. `TOuter<T> = class FOther: TOuter<ShortInt>; end;` was a MODE-DELPHI-ONLY defect -- the objfpc spelling `specialize TOuter<ShortInt>` always compiled and ran. Each template desugars the stream from its OWN end forward, so a different template's group inside this body is collapsed before capture and the template's own name is deliberately not; this third shape fell between and SpecializeToBuffer emitted `TOuter$LongInt<ShortInt>`. Fixed by normalising the Delphi surface at capture -- the `specialize` keyword the arena machinery already keys on -- so both surfaces now print the same row. FPC 3.2.2 compiles NEITHER surface. The parameter-SWAPPED case is refused by both surfaces with an honest cycle diagnostic and is split out."
---

# P: a different specialization of the same template, inside its own body

## The three cases, and only this one is broken

```pascal
type
  TBox<T>   = class V: T; end;
  TOuter<T> = class
    V: T;
    FBox:   TBox<ShortInt>;     { different TEMPLATE          -> ok, runs }
    FSelf:  TOuter<T>;          { same template, same args    -> ok, runs (fixed) }
    FOther: TOuter<ShortInt>;   { same template, DIFFERENT args -> FAILS }
  end;
```

Two-parameter form fails the same way when the arguments are reordered, which is
the same thing said differently — `TPair<V, K>` inside `TPair<K, V>` is a
different specialization:

```pascal
  TPair<K, V> = class
    FSelf: TPair<K, V>;     { ok }
    FSwap: TPair<V, K>;     { FAILS }
  end;
```

## Pre-existing, and NOT the double-substitution bug

Verified against `pinned` (sha256 `abece5150983d95e`) as well as HEAD: both fail,
with the same error on the single-parameter case.

It is specifically **not** the defect fixed in
[[bug-p-a-nested-class-naming-its-enclosing-template-is-substituted-twice]] —
neither shape produces that ticket's `TOuter$LongInt  LongInt` signature. The
order-matching guard added there deliberately declines to collapse these, which
is correct: they denote a different specialization and must keep their argument
list. They then fail further along, for this older reason.

Reported as the negative-case half of that ticket's sibling sweep: the fix was
checked from both sides, and this is what the other side turned up.

## Where to look

Almost certainly the nested-specialization PREREQUISITE path rather than
substitution — `TOuter<ShortInt>` needs its own specialization emitted before
`TOuter<LongInt>`'s body can refer to it, and the emitting template is the one
being specialized. `ParseSpecialization`'s prerequisite scan and
`NestedSpecKnown` are the places to start.

## Priority

Low: the shape is legal and real but uncommon (a container holding a differently
parameterised instance of itself), and it fails loudly at compile time rather
than silently producing a wrong value. Filed so it is not rediscovered as new.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 02a57e20e.

## Fixed 2026-09-04 (frankB) — and the ticket's premise needed correcting first

**This was mode-Delphi only, and the ticket did not say so.** Measured before
touching anything, at binary d54b46acea55:

| shape | pxx delphi | pxx objfpc | fpc 3.2.2 (either mode) |
| --- | --- | --- | --- |
| `FBox: TBox<ShortInt>` — a different TEMPLATE | ok | ok | ok |
| `FSelf: TOuter<T>` — same template, same args | ok | ok | ok |
| `FOther: TOuter<ShortInt>` — same template, DIFFERENT args | **`expected ':' before '>'`** | **ok, runs** | **refused** |

Two things that change the shape of the fix:

1. **The objfpc spelling already worked.** So nothing was missing from the
   specialization machinery — one SURFACE was not reaching what the other
   reaches. That makes this a `normalise-dont-special-case` case rather than a
   feature.
2. **FPC 3.2.2 refuses BOTH surfaces** (`Syntax error, "identifier" expected
   but ";" found`). So this is not an FPC-compat item at all; we already accept
   more than FPC here, which is not a defect. What made it worth fixing is that
   OUR TWO SURFACES DISAGREED, and that the mode-Delphi failure leaked an
   internal minted name (`TOuter$LongInt<ShortInt>`) into a user diagnostic.

### The mechanism, and why this one shape had no owner

Each template's mode-Delphi desugar sweep starts at its OWN end
(`dgenAt := finalCur`) and runs forward over the rest of the stream. So:

- `TBox<ShortInt>` inside `TOuter`'s body is collapsed to `TBox$ShortInt` by
  **TBox's** sweep, which happens before `TOuter` is captured. That is why a
  different template in that position always worked.
- `TOuter<...>` inside `TOuter`'s own body is reached by no sweep at all, and
  deliberately: `TOuter<T>` there means the specialization being built, and
  turning it into an alias would be wrong.

`TOuter<ShortInt>` is neither. It fell through to `SpecializeToBuffer`, whose
own-name arm rewrote the bare identifier to the specialization being built while
`SelfSpecGroupEnd` — correctly — declined to drop an argument list that is not
the template's own parameters. Result: `TOuter$LongInt < ShortInt >`, and
`expected ':' before '>'`.

### The fix: normalise the surface, do not grow a second recognizer

At capture, a mode-Delphi `TOuter<args>` inside `TOuter`'s own body, where args
are not exactly its own parameters in order, gets the `specialize` keyword
written in front of it. The arena content is then byte-for-byte the objfpc form,
`NestedSpecGroup` recognises it, `ScanRangeForNestedSpecs` registers
`TOuter$ShortInt` as a prerequisite and `SpecializeToBuffer` collapses the group
to that alias. **No downstream code changed.**

Three helpers, all asking of `Tokens[]` what the existing ones ask of the arena:
`TokSpecGroupEnd`, `TokGroupIsTemplateOwnParams`, `DelphiSelfSpecNeedsKeyword`.

### Measured after

```
1000000 7 1000000 3 1 4      { mode-Delphi arm  }
1000000 7 1000000 3 1 4      { objfpc arm       }
surfaces agree
```

**`SizeOf(o.FOther.V)` = 1 against `SizeOf(o.V)` = 4 is the load-bearing row.**
Every other column passes just as well if `FOther` were quietly collapsed into
the enclosing specialization; only the two widths say `TOuter$ShortInt` is a
genuinely distinct type. Neither value collides with a type default.

Positive control: the pinned binary (`c31d03b202da`) fails the new test with
this ticket's exact error, `expected ':' before '>'`.

### Split out, not fixed

The parameter-SWAPPED form — `FSwap: TPair<V, K>` inside `TPair<K, V>` — is now
refused by both surfaces with the same honest diagnostic the objfpc surface
always gave it: `circular generic specialization: TPair$LongInt$ShortInt
requires TPair$ShortInt$LongInt, which requires TPair$LongInt$ShortInt back`.
That is true as stated and architectural — pxx emits each specialization before
its users, and these two are each other's prerequisite. Filed at prio 20 as
[[bug-p-a-generic-cannot-hold-a-parameter-swapped-specialization-of-itself]].

### Test

`test/test_generic_self_other_specialization.pas` +
`generic_selfspec_units/uselfspec.pas` — the mode-Delphi arm and the objfpc
CONTROL, asserted equal row for row.
