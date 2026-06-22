# `done-followup/` — shipped, only optional polish left

Tickets here are **delivered and usable**; the feature works. They stay open only
because some explicitly-optional / low-priority follow-up remains (an enhancement,
a fancy, a deferred refinement) — nothing that blocks using the feature.

Example: `feature-interfaces` — the CORBA interface surface is complete
(declare/implement/assign/call, is/as/Supports, inheritance, all targets); only
automatic refcounting (ARC) is deferred, and it is not needed.

Distinction:
- vs `backlog/` — backlog is active, not-yet-delivered work.
- vs `rainy-day/` — rainy-day is parked work that is **not built yet** (big /
  not-directly-language-relevant / ideas / design parks).
- vs `done/` — `done/` is fully complete with nothing left; here a small optional
  remainder is acknowledged.

Move a ticket from here to `done/` when the remainder is actually finished, or
back to `backlog/` if the follow-up becomes active. `tools/progress.sh` knows
this status (own board column, README excluded from counts). It does **not**
satisfy `Blocked-by:` by default — if a shipped item here truly unblocks
something, prefer recording that dependency against `done/`.
