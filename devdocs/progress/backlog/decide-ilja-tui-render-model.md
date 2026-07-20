---
summary: "Track U: four render/input questions Ilja (TUI IDE face) must answer before any code"
type: decide
prio: 45
track: U
---

# decide: Ilja's render model — canvas seam, resize input, colour depth, px→cell mapping

- **Type:** decision — **Track U**. No files, no gate.
- **Status:** open — filed 2026-07-20.
- **Blocks:** [[feature-ilja-tui]].
- **Raised by:** Track B queue sweep. The ticket's own header says
  "resolve at start", and four unresolved design questions sat inside an
  implementation ticket that was ranked as available Track B work. It is not
  available: whichever way these go changes what gets built.

## B — shared thin canvas interface, or fully separate paint code?

The whole premise of Ilja is that garin is render-agnostic, and the acceptance
criterion is "garin needed no GUI-specific change". That is a claim a *second*
renderer tests; it is not a claim a shared canvas abstraction tests, because a
canvas seam designed while looking at two renderers will quietly absorb whatever
assumption leaked.

- **(a) Shared thin canvas.** Less duplicated paint code; risks the seam becoming
  a place GUI assumptions hide rather than get fixed.
- **(b) Fully separate paint.** Duplicated drawing, but any garin leakage shows
  up as "Ilja cannot express this", which is exactly the signal the ticket wants.

**Recommendation: (b) first, extract (a) later if the duplication actually
hurts.** The ticket's value is the falsification test; optimising away the
duplication before that test has run trades the point for tidiness.

## C — resize input: keyboard nudge, mouse drag, or both?

- Keyboard nudge is unambiguous, works over plain terminals and ssh, needs no
  mouse protocol.
- Mouse drag (xterm SGR 1006) matches the GUI face's feel but is terminal
  dependent, and a drag over a slow link is unpleasant.

**Recommendation: keyboard first, mouse as an optional additive layer.** The
ticket already calls mouse "optional"; making it the primary path would make the
TUI face unusable exactly where a TUI is most wanted.

## D — colour depth: 256, truecolor, or a 16-colour floor?

The repo already has truecolor precedent (`ansiterm`'s RGB helpers, the
mandelbrot TUI). But an IDE is not a demo: it runs over ssh, inside tmux, and in
terminals that lie about what they support.

**Recommendation: author in truecolor, degrade to 256 and to 16.** The floor
matters more than the ceiling for an editor. Deciding this late means colour
constants get sprinkled at call sites and the degrade path never gets written.

## Coord mapping — garin px → cells

garin models are in pixels; a cell is roughly 8x16. The rounding rule needs to be
one documented function, not per-call-site arithmetic, or box borders will
disagree with box contents by a cell at some zoom levels.

**Recommendation:** one `PxToCell`/`CellToPx` pair with an explicit rounding rule
(round-half-up on both axes, cell size a named constant), decided once and
asserted in a test, since off-by-one here is visible as broken box-drawing rather
than as a crash.

## Once decided

Fold the answers into [[feature-ilja-tui]] and drop its `blocked-by` edge. None
of this needs the user to design the IDE — it needs four small "which of these"
calls, and any of them can be reversed later at known cost.

## Log
- 2026-07-20 — Filed from the Track B sweep so the questions are visible as a
  decision rather than sitting unanswered inside implementation work.
