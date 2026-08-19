---
track: U
prio: 50
type: decide
blocked-by: []
summary: "bug-c-definition-of-an-intrinsic-name-overwrites-the-pascal-routine (C, p55) is the only thing blocking feature-a-own-language-first-symbol-resolution, and Track C is unstaffed. Staff it, fold it into an existing session, or leave the chain parked?"
---

# Decide: staff Track C, or leave the own-language-first chain parked

> **DECIDED — and it was decided BY ACTION on 2026-08-19, not in this ticket. Option 1.**
>
> Track C was folded into an existing session (frank2, alongside its A/P/C work) rather than
> given a fourth checkout — exactly the recommendation below, and for the reason given: the
> blocker was small and lane-safe, and C's files (`clexer`/`cparser`/`cpreproc`/`lib/crtl`)
> are disjoint from the `lexer.inc`/`parser.inc` another session was holding, so the two could
> not collide.
>
> **The blocker is FIXED: `eb5c7be11`**, and
> [[bug-c-definition-of-an-intrinsic-name-overwrites-the-pascal-routine]] is in `done/`.
> The chain behind it is unblocked;
> [[feature-a-own-language-first-symbol-resolution]] moved `blocked/` -> `backlog/` at p55.
>
> **Worth recording as the failure mode, because this ticket is an instance of it:** the
> decision was taken in practice hours before anyone updated the ticket, so for that whole
> window the board said a question was open that had already been answered — the mirror of
> "a decided ticket never re-filed is invisible work". **A decision executed but not written
> down is just as stale as one written down but not executed.** If you act on a `decide-*`,
> close it in the same pass.
>
> Note the fix took a *different instrument* than this ticket's recommendation implied: the
> discriminator is exact **case**, not unit-of-origin, because `lib/crtl` deliberately
> redefines Pascal builtins it spells identically (`malloc`, `memcpy`, `strtod`) and splitting
> those would give a program two allocators. So no `ProcLang` array and no Track A ticket fell
> out of it, as the ticket had anticipated they might.

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
