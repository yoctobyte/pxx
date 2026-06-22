# `done-followup/` — shipped-or-parked, not active work

Tickets here are **not active backlog**. The bucket folds together everything
that is real but not something anyone is about to pick up, so the active
`backlog/` reflects actual near-term work. Three flavours live here:

1. **Shipped-core, polish-only.** The feature is delivered and usable; what
   remains is explicitly optional / low-priority (e.g. `feature-interfaces` —
   CORBA surface complete, only automatic refcounting deferred).
2. **Deferred / rainy-day.** Not started, deliberately low priority — a future
   profile, an exotic target, a speculative allocator, a stretch goal.
3. **Design parks.** Standing decisions intentionally left open (no action until
   a call is made).

Moving a ticket here is **reversible** — pull it back to `backlog/` when it
becomes active, or to `done/` when the remainder is actually finished.

`tools/progress.sh` knows this status (it shows as its own board column and is
exempt from the `done/`-only "must log a commit" check). It does **not** satisfy
`Blocked-by:` dependencies — only true `done/` does — since this bucket includes
not-yet-built items.

Convention: a ticket moved here should have its `Status:` updated to note the
flavour (e.g. `done-followup — shipped; ARC deferred`, or `done-followup —
deferred/rainy-day`).
