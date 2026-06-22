# `done-followup/` — parked: shipped, or big/tangential, not active work

Tickets here are **not active backlog** — but "parked" does **not** mean
"unimportant or uninteresting." It mostly means **big work and/or not directly
language-relevant** (a new backend/OS port, runtime/allocator infra, debug
tooling, a stretch goal), set aside so the active `backlog/` reflects the
near-term language/compiler work. Flavours:

1. **Shipped-core, polish-only.** The feature is delivered and usable; what
   remains is explicitly optional (e.g. `feature-interfaces` — CORBA surface
   complete, only automatic refcounting deferred).
2. **Big / not directly language-relevant.** Substantial undertakings that are
   tangential to the core language: extra CPU targets, OS ports, allocator
   profiles, DWARF debug info, coroutine-runtime ports, parallel infra. Worth
   doing — just not the current language focus.
3. **Design parks.** Standing decisions intentionally left open (no action until
   a call is made).

Counterpoint: a *language-relevant* feature (a directive, a type-system or
codegen capability) stays in `backlog/` even when low priority — that's the line.

Moving a ticket here is **reversible** — pull it back to `backlog/` when it
becomes active, or to `done/` when the remainder is actually finished.

`tools/progress.sh` knows this status (it shows as its own board column and is
exempt from the `done/`-only "must log a commit" check). It does **not** satisfy
`Blocked-by:` dependencies — only true `done/` does — since this bucket includes
not-yet-built items.

Convention: a ticket moved here should have its `Status:` updated to note the
flavour (e.g. `done-followup — shipped; ARC deferred`, or `done-followup —
deferred/rainy-day`).
