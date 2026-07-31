

## DECIDED 2026-07-20 — hybrid now, cells as the end state

**User's call: the hybrid, with cells as the destination.**

- **Now:** a def whose name is only ever CALLED keeps today's trailing
  by-value parameters — already shipped, gated, zero heap. A def used as a
  VALUE gets a closure record.
- **End state:** cells. They are the correct model — proper late binding, and
  `nonlocal` falls out free — and adopting them changes only WHERE the
  captured storage lives, not the surface semantics.

So the common call-only case keeps costing nothing, and the correct model
stays reachable without a rewrite. Cells-everywhere-now was rejected for
charging heap allocation to the case that dominates; by-value-only was
rejected for foreclosing a normal Python idiom the frontend already partly
supports.

## Log
- 2026-07-20 — resolved, commit PENDING.
