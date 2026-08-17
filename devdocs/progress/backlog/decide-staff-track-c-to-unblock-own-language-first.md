---
track: U
prio: 50
type: decide
blocked-by: []
summary: "bug-c-definition-of-an-intrinsic-name-overwrites-the-pascal-routine (C, p55) is the only thing blocking feature-a-own-language-first-symbol-resolution, and Track C is unstaffed. Staff it, fold it into an existing session, or leave the chain parked?"
---

# Decide: staff Track C, or leave the own-language-first chain parked

**Read time ~1 minute.**

`bug-c-definition-of-an-intrinsic-name-overwrites-the-pascal-routine` sits at
p55 in Track C and is the single unmet blocker on
`feature-a-own-language-first-symbol-resolution`. Nobody is on Track C.

The fix is in `cparser.inc` — C's own file, so it does NOT collide with A/P/N and
needs no pin.

## Options

1. **Fold C into an existing session.** Frontend+frontend is the low-risk combo
   (disjoint files), so whoever holds N or B could take it. Cheapest.
2. **Staff a 4th checkout for C.** Clean, but adds a session to supervise and a
   fourth compile stream on an 8-core box already running three.
3. **Leave it parked.** It has waited this long; the chain behind it is one
   feature.

## Recommendation

**(1), folded into whichever session is free first** — but not before the
current three run a clean day. The blocker is small and lane-safe; the cost is
attention, not risk.

Related standing note: "own language first" is already a settled principle
(memory: own-language-first name resolution beats cross-language AND overrules
import order). This is about who does it, not whether.
