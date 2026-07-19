---
track: A
prio: 10
type: idea
---

# Warn when a call name matches in BOTH the Pascal and C namespaces

- **Track:** A (FindProc / symtab) with C-frontend touch. Rainy-day.
- **Opened:** 2026-07-19, side effect of the two-libm approach
  (feature-crtl-libm-correctly-rounded-transcendentals).

The case-insensitive C/Pascal proc namespace is what made a C `exp`
definition next to Pascal `Exp` silently break call binding (b377 — the
argument never arrived). The crtl fix (\_\_crtl\_ names + macros) removes the
collisions we know about, but the FAILURE MODE is still silent for the next
one.

Proposal (user sketch):
1. **Deterministic search order by source language**: a call from Pascal
   source resolves Pascal RTL first; a call from C source resolves crtl/C
   procs first. (Largely true today by accident of registration order —
   make it explicit.)
2. **Compiler warning when more than one candidate matches** a call across
   the namespaces (differing only by case / origin), so the next exp/Exp
   pair is loud instead of silent garbage.
3. Same idea one level up: warn when multiple units in the search path
   provide the same routine name.

Minor, diagnostics-only — no behavior change without a decide. Gate: warning
fires on a synthetic exp/Exp twin, quiet on the normal corpus builds.
