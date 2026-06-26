# `rainy-day/` — parked: real but not the current focus

Tickets here are **not active backlog** and **not yet shipped** — but parked does
**not** mean "unimportant or uninteresting." It mostly means **big work and/or
not directly language-relevant**, deliberately set aside so the active
`backlog/` reflects near-term language/compiler work. What lives here:

- **Big / not directly language-relevant:** extra CPU targets, OS ports,
  runtime/allocator infra, DWARF debug info, coroutine-runtime ports, backend
  auto-selection, bounded/arena memory profiles.
- **Ideas / stretch goals / policy:** speculative demos, a `uses X as Y` import,
  visibility enforcement, "compile the FPC compiler", the FPC-vs-PXX boundary
  doc.
- **Design parks:** standing decisions intentionally left open (no action until a
  call is made).

The line vs `backlog/`: a **language-relevant** feature (a directive, a
type-system or codegen capability) stays in `backlog/` even when low priority.
The line vs `done-followup/`: that bucket is for features that are **shipped and
usable** with only optional polish left; rainy-day items are not built yet.

Moving here is **reversible** — pull back to `backlog/` when it becomes active.
`tools/progress.sh` knows this status (own board column, README excluded from
counts); it does **not** satisfy `Blocked-by:` (nothing here is done).
