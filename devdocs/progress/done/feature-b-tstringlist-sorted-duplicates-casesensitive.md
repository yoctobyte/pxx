---
summary: "TStringList gained Sorted / Duplicates / CaseSensitive / Find, and Sort is now case-insensitive like FPC's — it had been comparing with CompareStr, so `Sort` on (Banana, apple, Cherry) gave ASCII order"
type: feature
track: B
prio: 50
---

# TStringList: `Sorted`, `Duplicates`, `CaseSensitive`, `Find`

- **Type:** feature + bug — Track B (`lib/rtl/classes.pas`)
- **Status:** done
- **Opened / closed:** 2026-08-05
- **Found by:** `tools/fpc_diff_probe.sh`, the generics/interfaces/TStringList
  batch — the surface the 2026-08-04/05 handoff named as untouched.
  `sl-sorted-prop` had been sitting as a `known` divergence.

## What was missing

`Sorted`, `Duplicates`, `CaseSensitive` and `Find` did not exist; `l.Sorted := True`
was `"Sorted": no such member on this record/class`. Only an unconditional
`Sort` was there.

## The bug hiding underneath

`Sort` compared with `CompareStr` — **case-sensitive**. FPC's `TStringList`
compares case-INSENSITIVELY unless `CaseSensitive` is set, so:

```pascal
l.Add('Banana'); l.Add('apple'); l.Add('Cherry'); l.Sort;
```

gave `Banana Cherry apple` (ASCII) where FPC gives `apple Banana Cherry`. Any
sorted list of mixed-case strings — filenames, headers, identifiers — came out
in the wrong order, silently.

## What landed

Following FPC:

- `CompareStrings` is the **single** place ordering is decided, so `Sort`,
  `Find`, `IndexOf` and the sorted `Add` cannot disagree about it. That
  matters: `Find` is a binary search, and a search using a different comparison
  than the one that ordered the list reports a miss for a string that is
  present.
- `Sorted := True` sorts and then maintains order on every `Add`;
  `Sorted := False` stops maintaining it and **leaves the current order** (does
  not restore the original).
- `Duplicates` (`dupIgnore` default, `dupAccept`, `dupError`) applies only while
  sorted. `dupIgnore` returns the EXISTING index, so `AddObject` on a duplicate
  retargets the object as in FPC.
- `IndexOf` uses the binary search when sorted, the linear scan otherwise.
- `CaseSensitive` re-sorts a sorted list when it changes — otherwise the list
  stays ordered by the *old* comparison and `Find` silently breaks.
- `Insert` at a caller-chosen index **raises** on a sorted list, as FPC does,
  rather than leaving a list marked sorted but not ordered. `Add` is the sorted
  entry point; both go through a private `InsertItem`.

## Tie order among case-equal strings is UNSPECIFIED

Worth recording, because it looked like a regression. The existing probe
`sl-sort-dups` compares the exact output of sorting `('b','a','b','A')`, and it
had been **passing for the wrong reason**: pxx's case-sensitive comparison put
`'A'` before `'a'` on ASCII, which happened to match FPC.

Measured on FPC: `('a','A')` sorts to `a A` and `('A','a')` to `A a` — stable —
but `('b','a','b','A')` gives `A a b b`. Its quicksort is stable for a short run
and not for a longer one, so the relative order of case-equal entries is an
artifact, not a contract. pxx's insertion sort is stable throughout.

`sl-sort-dups` is therefore tagged `known` with that explanation, and two cases
cover what *is* specified: `sl-sort-dups-defined` (count + non-decreasing
case-insensitive order + the multiset) and `sl-sort-casesensitive` (four
entries that compare pairwise unequal, so tie order cannot matter).

## Regression cover

Six new probe cases — `sl-sorted-on`, `sl-sorted-insert-order`,
`sl-sorted-indexof`, `sl-dup-ignore`, `sl-sorted-off-keeps-order`,
`sl-sort-method` — plus the two above, all byte-matched against FPC.

## Gate

`fpc_diff_probe` 195 cases, 0 new divergences; `gate.sh quick` + `gate.sh lib`
green; `lib_cross_sweep` clean.
