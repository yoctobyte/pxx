---
prio: 45  # auto
blocked-by: [decide-gpc-as-corpus-target]
---

# Wish: compile GPC

- **Type:** wish
- **Track:** B+C
- **Status:** backlog
- **Opened:** 2026-06-30

Compile GNU Pascal (GPC) under pxx. GPC's compiler is C (gcc frontend) —
Track C; its runtime library is Pascal (ISO 7185/10206, partial Turbo
Pascal) — Track B. Opportunistic, not scoped. Source: gnu-pascal.de /
`hebisch/gpc`. File follow-up tickets for whatever breaks.

- 2026-07-19 (backlog sweep note) Rejection candidate (user call): sibling analysis in idea-c-realworld-test-targets argues gpc is a GCC frontend, not standalone-buildable — recommends p2c/tcc instead, and tcc self-compile is DONE. Recommend moving to rejected/ or folding into that idea ticket.

## Track B note (2026-07-20) — awaiting a user call, not work

Carried a "rejection candidate (user call)" sweep note and was still ranked at
prio 45 in the Track B ready queue, so it read as available work. It is not:
whether to support GNU Pascal at all is a scope decision, and scope decisions
are Track U.

Recommendation, for whoever makes the call: **reject.** GNU Pascal is a dead
dialect (last release 2005) with extensions that do not overlap the
FPC/Delphi surface the Pascal frontend targets, so the work would not feed the
compat campaign that Synapse/fgl/FPC-itself do. Left in place rather than moved,
because moving it to `rejected/` IS the decision and that is the user's to make.

Blocked on [[decide-gpc-as-corpus-target]] (2026-07-20) so it stops appearing as
available Track B work while it waits on a scope call.
