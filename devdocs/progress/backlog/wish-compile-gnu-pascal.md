---
prio: 45  # auto
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
