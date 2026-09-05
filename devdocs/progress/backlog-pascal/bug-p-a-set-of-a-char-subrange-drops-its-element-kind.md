---
slug: bug-p-a-set-of-a-char-subrange-drops-its-element-kind
title: "`Low`/`High` of a `set of 'c'..'k'` answer 99 and 107 where fpc answers c and k"
track: P
prio: 35
type: bug
status: backlog
owner: ""
created: 2026-09-05
found-by: frankB
blocked-by: []
summary: "Split out of bug-p-a-type-alias-drops-the-enum-identity-and-a-set-drops-its-char-element-kind, whose other half is fixed. The BOUNDS survive (99 and 107 are the right ordinals) — it is the element KIND that is dropped, so they print as integers. `set of 1..10` and `set of sat..sun` are correct, the latter only because the probe reads it through `Ord`. ParseSetElemSpec keeps the LAST of the three 'parse lo..hi' copies, guarded on `tkInteger`, so a CHAR subrange element takes the `else ParseTypeKind` branch and the element kind is recorded from a path that never set it. Folding that copy is the likely fix and it needs its own verification pass, because `Low`/`High` of a set TYPE NAME is refused outright here (`undefined variable`), so half the natural assertions do not exist yet."
---

# The measurement

```pascal
var b: set of 'c'..'k';
WriteLn(Low(b), ' ', High(b));   { pxx: 99 107    fpc: c k }
```

Verified PRE-EXISTING against pin v403.

# Why it was split from its filing partner

The parent ticket carried two defects under one slug, and they turned out to
share a family and not a mechanism. Half 1 was **one missing column** in
`RegisterGeneralAlias` plus its read sites — fixed 2026-09-05, and the fix
touched nothing this half needs. Half 2 is the third copy of a subrange parse
and a `Low`/`High` question that is not answerable yet.

A reader who took the parent slug at face value would have fixed half 1 and
closed the ticket, which is the failure the Track P campaign is grouping by
CONSTRUCT to avoid.

# What it needs, in order

1. **`Low`/`High` of a set TYPE NAME** — refused today with
   `undefined variable (SI)`. Until that answers, only the set-VARIABLE
   spelling can be asserted, which is half a test.
2. **Fold the third `parse lo..hi` copy.** The other two were folded into one
   shared body on 2026-09-05; `ParseSetElemSpec` still has its own, guarded on
   `tkInteger`, which is exactly why a char subrange misses it. Folding is the
   likely fix rather than adding a char arm to the copy.

# The fork this sits under

[[decide-how-a-type-carries-an-identity-its-kind-cannot-hold]] (Track U, p55)
