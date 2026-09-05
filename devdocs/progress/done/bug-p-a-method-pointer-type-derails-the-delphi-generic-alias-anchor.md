---
slug: bug-p-a-method-pointer-type-derails-the-delphi-generic-alias-anchor
track: P
prio: 55
type: bug
status: done
blocked-by: []
summary: "FIXED. DGenDeclAnchor counted the `object` in a method-pointer type (`TCb = function(x: Integer): Integer of object;`) as opening a type body. It opens nothing, so the depth went up and never came back down; with depth stuck above 0 the walk's `implementation` arm -- guarded on depth = 0 -- never fired, the walk left the type section it exists to stop at, and the routine bodies it then crossed each decremented on their own `end` until the count reached 0 in the middle of the implementation, where a `;` reads as a declaration boundary. The minted alias was spliced BETWEEN TWO ROUTINE BODIES with no `type` in force. Guarded on the PRECEDING token (`of`), not on the word: not counting `object` at all is the wrong fix and arm 3 of the test proves it, splicing the alias between a real object type's fields. Regression from b613b5fcf (2026-08-31), bisected with pin-seeded builds; it silently broke corpus rung 6a (rtl-generics Generics.Defaults, five `of object`), which feature-pascal-corpus-expansion still recorded as green from two independent sessions six days earlier. 6a compiles again and 6b is back at its own documented wall."
owner: frankB
---

# `of object` derailed the mode-Delphi generic alias anchor

## What broke, and how it was found

`tools/progress.sh next --track P` handed over `feature-pascal-corpus-expansion`,
whose canonical table recorded rung 6a (`generics.defaults`) as compiling end to
end, twice, from two independent sessions, with byte-identical figures
(`code=671512B procs=1661`). Re-measured at tip it failed outright:

```
pascal26:1064: error: unexpected token in a unit implementation section:
                      it starts no declaration (a mistyped section header?)
  in: .../generics.defaults.pas
  near: ( AComparison ) ; end ; >>> THashService$TDelphiHashFactory  specialize
```

`$` cannot occur in Pascal source, so the token stream had a MINTED alias in it.
6b, which had its own wall, now stopped inside 6a's file — the ladder had moved
BACKWARDS, and a recorded rung reads as a floor.

Two confounds this corpus has been burned by before were checked first: the
corpus bytes are identical to the FPC system copy (`md5sum` on both spellings —
same program, not a different one), and the failure reproduces under frankwasm's
exact recorded invocation, not only under a re-derived one. The PIN is not a
usable control here — it cannot build the current `lib/rtl` at all, a different
failure that would have read as corroboration.

## Root cause

`DGenDeclAnchor` walks forward from a template to a use of it, tracking
class/record/interface/object body depth, and anchors the minted alias after the
last depth-0 `;`. `interface` and `object` are counted because in a type section
they are type constructors.

`of object` is not one. In `TCb = function(x: Integer): Integer of object;` the
`object` opens nothing and there is no `end` to match it, so each one leaves the
depth permanently one higher.

**One is enough to break a whole unit.** The chain:

1. depth is stuck above 0 for the rest of the interface;
2. the `implementation` arm is guarded on `depth = 0`, so the walk does not stop
   where the type section ends;
3. every routine body it then crosses decrements on its own `end` — nothing
   incremented for those — so the count drifts back down;
4. it reaches 0 somewhere in the middle of the implementation, and the next
   depth-0 `;` there is recorded as a declaration boundary;
5. the alias is spliced between two routine bodies, with no `type` in force.

`Generics.Defaults` has five `of object`, three of them after the template. The
use is at line **2819**, inside a routine body:

```pascal
class function TDelphiHashFactory.GetHashService: THashServiceClass;
begin
  Result := THashService<TDelphiHashFactory>;
end;
```

and the alias landed at line **1064** — about 1750 lines before the use that
caused it, which is why the reported and the fixable location were nowhere near
each other for the second time in this function's life.

## The fix, and why the obvious one is wrong

Guard on the preceding token:

```pascal
(DGenIdentIs(k, 'object') and ((k = 0) or (Tokens[k-1].Kind <> tkOf)))
```

Not counting `object` at all passes arms 1, 2, 4 and 5 of the test and is
**wrong**: a real `TOld = object F: Integer; G: Integer; end` IS a body, and
uncounted, the `;` between its fields becomes a candidate anchor. Measured, with
that version built:

```
pascal26:93: error: expected ':'
  near: ; G : Integer ; TBox3$TArg >>>  specialize TBox3
```

The alias spliced between the object's own fields. Arm 3 exists for exactly this
and is the reason the test can tell the two fixes apart.

**This is the third entry in this walk's keyword list to be wrong, each in a
different direction.** `constructor`/`destructor` were soft keywords missing from
a list of hard ones (`bug-p-an-out-of-line-generic-constructor-broke-specialization`).
`implementation` is correctly soft. `object` is a real type constructor that is
also a modifier word. A list of keywords is not a list of concepts, and the
discriminator here is the neighbouring token rather than the token.

## Attribution

Bisected over 3425 commits, `4f42b78b9` (GOOD) to `36d7e5fd4` (BAD), first bad
commit **`b613b5fcf`** — the commit that introduced the anchor walk. Before it,
every alias went behind the template, where this shape happened to be legal.

**The bisect's own first run was invalid and the correction is worth keeping.**
Seeding each step from the binary the previous step left behind means the
compiler doing the building changes at every step — a moving instrument over a
moving tree — and it also simply does not work: a tip compiler refuses six-day-old
compiler sources (`LoadFile expects string variables in IR codegen` in
cpreproc.inc). That came out as five consecutive build SKIPs and a range that
never narrowed, which is a degenerate bisect wearing the shape of a running one.
Reseeding from the PIN at every step — the one fixed point outside the window —
made it converge in 12 steps. `tools/gate.sh`'s stale-binary note is the same
hazard one operation over.

## Test

`test/test_delphi_generic_of_object_anchor.pas` + `.pas` helper unit
`test/dgen_of_object_unit.pas`, `.expected` is fpc 3.2.2's own output. Six rows.

- arm 1 — a method-pointer type between template and use
- arm 2 — **negative control**: the same declaration without `of object`, which
  never broke; arm 1 alone cannot tell a fix from a coincidence
- arm 3 — **the discriminating arm**: a real `object` body between template and
  use; fails under the original bug AND under the lazy fix
- arm 4 — both, so the walk must tell them apart rather than pick one rule
- arm 5 — `of object` as a class field's type, inside a body that IS counted
- `unit` — the corpus shape proper: the use in a routine body in a unit's
  IMPLEMENTATION, the only place the original diagnostic can be produced

**Each arm gets its own type section, closed by the function that uses it**, and
that is not tidiness: in one shared section every arm's walk crosses every later
arm's declarations, so the arms mask each other and a failure cannot be
attributed to the shape it names. Measured — as one section, arm 5 failed for
arm 6's reasons.

## Result

Rung 6a compiles end to end again (`code=687896B data=138472B bss=127228B
procs=1780`; the figures differ from the six-day-old recorded green because
codegen moved in between, and are NOT claimed to match it). Rung 6b is back at
its own documented wall, `for-in: enumerator has no readable Current` at
`generics.collections.pas:1481`, which
[[feature-pascal-corpus-expansion]] records as a pin-ordering dependency rather
than a bug.

## Left open, deliberately

While reading the walk I saw that a generic parameter CONSTRAINT spelled
`<T: class>` reaches the `tkClass` arm and `DGenClassOpensBody` answers true for
it, so a template declared after another template appears to increment the depth
for its own constraint. Every arm of the test passes, so if it is real it is
masked here. Not measured, not claimed, and not fixed in this commit —
recorded so it is not re-derived from scratch.
