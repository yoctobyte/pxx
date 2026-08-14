---
track: B
prio: 45
type: bug
owner: track-b-bughunt
blocked-by: []
summary: "TStringList had THREE string comparisons for one concept and two of them ignored CaseSensitive, in opposite directions: IndexOf compared with `=` so it stayed case-SENSITIVE at the default (which is insensitive) and missed a present string; IndexOfName/Values hardcoded SameText so they stayed case-INSENSITIVE with CaseSensitive := True and matched a string they should not. Only Find/Sort went through CompareStrings. Fixed by moving CompareStrings up to TStrings as the single virtual every lookup uses."
status: done
---

# `TStringList` lookups use three different comparisons, two wrong

- **Type:** bug (wrong result) — **Track B** (`lib/rtl/classes.pas`).
- Found 2026-08-14 by an FPC 3.2.2 differential sweep of the `classes` surface.
- Textbook `devdocs/dev/normalise-dont-special-case.md`: one concept reachable
  through three code paths, and the two that could not see the flag each grew
  their own answer — wrong in **opposite** directions, which is why neither was
  obviously suspicious on its own.

## Measured — pxx vs FPC 3.2.2

`CaseSensitive` defaults to **False** in both, and that default was already
right; what disagreed was whether the lookups honoured it.

```pascal
sl.Add('Alpha'); sl.Add('beta'); sl.Add('GAMMA');
```

| | before | FPC |
| --- | --- | --- |
| `IndexOf('alpha')` (default, insensitive) | **-1** | 0 |
| `IndexOf('ALPHA')` | **-1** | 0 |
| `IndexOf('BETA')` | **-1** | 1 |
| `IndexOf('gamma')` | **-1** | 2 |
| `IndexOf('Alpha')` exact | 0 | 0 |

```pascal
sl.Add('Key=val');  sl.CaseSensitive := True;
```

| | before | FPC |
| --- | --- | --- |
| `IndexOfName('key')` | **0** | -1 |
| `Values['key']` | **'val'** | `''` |
| `IndexOfName('Key')` exact | 0 | 0 |

So `IndexOf` was too strict and `IndexOfName`/`Values` too lax, and each was
wrong exactly where the other was right.

## Cause — three mechanisms

| path | compared with | honoured `CaseSensitive`? |
| --- | --- | --- |
| `TStringList.Find` / `Sort` / sorted `Add` | `CompareStrings` | **yes** |
| `TStrings.IndexOf` | `Get(i) = S` | no — always sensitive |
| `TStrings.IndexOfName` (and `Values` through it) | `SameText(...)` | no — always insensitive |

`CompareStrings` was declared on **TStringList**, so the two lookups inherited
from `TStrings` could not reach it and each hardcoded a comparison instead.
`TStringList.IndexOf` delegates to `inherited IndexOf` when the list is
unsorted, which is how the sorted and unsorted paths of the *same method* came
to disagree: sorted went through `Find` (correct), unsorted through `=`.

FPC does not have this split — its `CompareStrings` is virtual on `TStrings`
precisely so every lookup shares it.

## Fix — delete cases, do not add them

`CompareStrings` moves **up to `TStrings`** as a `virtual`, defaulting to
`CompareText` (case-insensitive, FPC's default for a bare `TStrings`).
`TStringList` keeps its body and marks it `override`. `TStrings.IndexOf` and
`TStrings.IndexOfName` then route through the virtual.

Net effect: **one** comparison mechanism where there were three, and
`TStringList.IndexOf`'s unsorted path is fixed without being touched — it calls
`inherited IndexOf`, which now dispatches back to `TStringList`'s override. The
diff removes a `SameText` and a `=`; it adds no branch.

The stale interface comment on the Name=Value block ("Name matching is
CASE-INSENSITIVE, as FPC's is") was true only by accident and is now covered by
the virtual, which follows the flag as FPC does.

## Gate

The two tables above match FPC on every row, plus the sorted/unsorted and
`CaseSensitive` True/False cross-product for `IndexOf` (all four combinations
verified), and a 20-row `TStringList` sweep — `Sort`, `CommaText`, `Values`,
`Names`, `Insert`/`Delete`/`Clear`, quoted `CommaText` parsing — unchanged and
identical to FPC. `make lib-test` green.

## Log
- 2026-08-14 — resolved, commit 8f6e4a794.
