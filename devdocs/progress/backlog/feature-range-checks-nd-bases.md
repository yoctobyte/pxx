---
summary: "{$R+} follow-up: N-D static-array bases — per-dimension index checks (a[i,j] checks i and j against their own lo..hi)"
type: feature
prio: 25
---

# {$R+} N-D bases (the last unchecked index shape)

- **Type:** feature (continuation of [[feature-pascal-range-checks-r-plus]],
  resolved at FPC parity for the common surface). **Track A.**
- **Opened:** 2026-07-15.
- N-D static arrays flatten at parse: the composed index
  (i-lo1)*span2+(j-lo2) reaches IR as one expression, so the central
  IRLowerAddress guard cannot recover the per-dim bounds. Wrap EACH
  subscript at its parse-composition site (under StmtRChecks) with
  IRWrapChkBounds-equivalent AST calls — dims live in SymArrDimLo/Span and
  UFldArrDimLo/Span. Oracle-probe FPC first per the arc's standing lesson.
