---
track: P
prio: 60
type: bug
blocked-by: []
status: open
owner: frankS
summary: "The `generics.collections` wall `too many deferred specializations` is a NON-CONVERGING SPECIALIZATION LADDER, not a missing dedup and not a cap that is too small. Measured 2026-09-09 at binary 5e00cec21466 / bab3814ad: `PXXDBG=p.mint:*` gives 872 mints whose distinct aliases bucket as 10 per rung across 55 rungs, and `p.nspec` names the pump in one row per rung — the SUBSTITUTION at rung N+1 is rung N's alias (`subs=T->TEnumerable$UInt32$PT` mints `TCustomPointersEnumerator$TEnumerable$UInt32$PT$PT`, whose own registration then reads `subs=T->TEnumerable$TEnumerable$UInt32$PT$PT`). The seed is the shape DbgMintTrace's own comment says the p.mint probe exists to catch: `alias=TCustomPointersEnumerator$UInt32$PT under=TCustomListWithPointers$UInt32 nsub=1 subs=T->UInt32` — a two-argument reference registered with ONE substitution in force, so the second argument is carried into the name as the still-unsubstituted parameter name `PT`. The template is generics.collections.pas:144 `TCustomPointersEnumerator<T, PT> = class abstract(TEnumerator<PT>)`, used at :212, and `PT` is ALSO the name of `TEnumerable<T>`'s nested `PT = ^T` (:131) — one spelling, two bindings. The per-name deferral cap cannot stop it: `SpecDeferRound` is counted per specName and every rung is a NEW name, so `circular generic specialization` never fires and `too many deferred specializations` (SpecDeferCount vs MAX_SPECIALIZATIONS = 256) is what gives out. RAISING THE CAP IS NOT THE FIX AND WAS MEASURED: at 1024 the run reaches `token character pool overflow` with one alias carrying ~120 `TEnumerable$` and ~130 `$PT`. NOT the mangler: all 872 aliases are exactly `tmpl + '$' + join('$', args)` (0 exceptions), and an earlier revision of this ticket claiming a name-vs-args surplus was a substring-counting artifact, corrected here."
---

# A specialization ladder that gains an argument segment per round

**Blocks [[feature-pascal-corpus-generics]]** — this is the `uses Generics.Collections`
wall on rung 3, at binary `5e00cec21466` (`bab3814ad`).

## The ladder, and the row that names the pump

`PXXDBG=p.mint:*`, driver `uses Generics.Collections`, corpus staged at
`library_candidates/rtl-generics/packages/rtl-generics/src`: **872 mints**, and
the distinct aliases bucket by how many `TEnumerable$` segments they carry —
109 at zero, then exactly **10 aliases at each of rungs 1..54**, 3 at rung 55.

`PXXDBG=p.nspec:TCustomPointersEnumerator` says why, one row per rung:

```
alias=TCustomPointersEnumerator$UInt32$PT
      under=TCustomListWithPointers$UInt32   nsub=1 subs=T->UInt32
alias=TCustomPointersEnumerator$TEnumerable$UInt32$PT$PT
      under=TQueue$TEnumerable$UInt32$PT     nsub=1 subs=T->TEnumerable$UInt32$PT
alias=TCustomPointersEnumerator$TEnumerable$TEnumerable$UInt32$PT$PT$PT
      under=TQueue$TEnumerable$TEnumerable$UInt32$PT$PT
                                             nsub=1 subs=T->TEnumerable$TEnumerable$UInt32$PT$PT
```

The substitution at rung N+1 is the alias minted at rung N. 55 rungs, and the
only thing that stops it is `MAX_SPECIALIZATIONS = 256`.

## Where it starts — one spelling, two bindings

```pascal
TEnumerable<T> = class abstract
public type
  PT = ^T;                                                          // :131
...
TCustomPointersEnumerator<T, PT> = class abstract(TEnumerator<PT>);  // :144
...
  TPointersEnumerator = class(TCustomPointersEnumerator<T, PT>)      // :212
```

At :144 `PT` is the template's own SECOND PARAMETER. At :212 the bare `PT` is
the nested type inherited from `TEnumerable<T>`. The seed row registers the :212
reference with **`nsub=1`, `subs=T->UInt32`** — one substitution for a
two-argument reference — so the second argument goes into the alias as the
literal parameter name `PT`. That is precisely the defect shape `DbgMintTrace`'s
own comment says the `p.mint` probe was written to catch: *"an argument that is
still a template PARAMETER name … means the mapping through `SpecSub*` in
`NestedSpecArg` did not happen or ran under the wrong substitution set."*

**What is NOT yet measured, and it is the next question:** why round N+1's `T`
comes back wrapped as `TEnumerable$<round N>$PT` — i.e. why the resolution of
`PT` lands as the FIRST argument of a fresh outer specialization instead of
filling the second slot of the existing one. Do not fix from the paragraph above
without measuring that; it is a reading of two probes, not a third measurement.

## Why nothing bounds it

There IS a round cap and it cannot see this: `SpecDeferRound[]` is counted per
`specName`, and `circular generic specialization` fires only when ONE name is
deferred more than `MAX_SPECIALIZATIONS` times. Every rung is a new name, so
each one is deferred once and the counter never climbs. What gives out is
`SpecDeferCount` — the number of DISTINCT deferred specializations — reported as
`too many deferred specializations`. A ladder is invisible to a per-name cap by
construction; only a cap on total deferrals, or on argument-name depth, would
see it.

## Two things NOT to do

- **Do not raise the cap.** Measured: `MAX_SPECIALIZATIONS = 1024` (binary
  `860aca3da02e`, experiment reverted, not landed) trades the diagnostic for
  `pascal26:30: error: token character pool overflow` with ~120 `TEnumerable$`
  and ~130 `$PT` in one alias. Same runaway, worse readout.
- **Do not go after the mangler.** All 872 mints satisfy
  `alias = tmpl + '$' + join('$', args)`, zero exceptions. **The first revision
  of this ticket (`de029d555`) claimed 110 mints whose alias carried more `$PT`
  than their `args=`, and that was a counting artifact** — the alias spells the
  separator (`$PT`) and the argument does not (`PT`), so the substring counts
  differ for names that agree exactly. The name IS a function of the arguments;
  the arguments are what runs away.

## Relation to the nested-type ticket

[[bug-p-a-class-nested-type-as-a-specialization-argument-resolves-at-unit-scope]]
is adjacent and **deliberately not merged**: that ticket's own summary says it is
not this rung's blocker, and `unknown type: PT` here was cleared by `1c16d4523`.
This ticket does not depend on it owning anything. The question that would merge
them: make the :212 `PT` resolve to `TEnumerable<T>.PT` and see whether the mint
count drops to one rung.

**Dead end already paid for:** extending `CollectHoistCandidates` to walk the
ancestor chain (so `PT` is found through `TEnumerable<T>`) HANGS this driver —
>90s, 176 mint lines, then `unknown type: TList$UInt32$PT`.
