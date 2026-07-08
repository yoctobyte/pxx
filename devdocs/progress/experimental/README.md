# experimental/ — optional frontends, permanently out of the queue

Created 2026-07-08 (user decision, Track Z session). Holds every ticket for
the **experimental frontends — Zig and Rust** — which stay *totally
experimental and optional*:

- Tickets here **never rank**: `next`/`ready` only pull from backlog/urgent,
  so nothing in this folder competes with real work, regardless of its
  `prio:` frontmatter. Pick one up only when the user asks for it (or it
  genuinely sounds fun in an idle session — same spirit as the esoteric
  probes).
- **Upscale rule:** if a ticket here turns out to be genuine AST/IR work
  (a new shared primitive — tagged unions, slices, drop tracking — that
  the CORE wants on its own merits), it may be promoted: refile it as a
  Track A ticket in `backlog/` with its own justification. The Zig/Rust
  frontend need alone is NOT that justification.
- Anything Track A that is merely *Zig-related* (or Rust-related) is low
  priority by default and belongs here, not in backlog.
- This is a parking state like `rainy-day`, not a live lock like
  `working/` — tickets here carry no freshness obligation.

Status snapshot at creation: Rust parked at 3/12 sub-tickets (proof of
concept done); Zig at "theoretic completion" — everything reachable by pure
parse-time desugaring onto the existing IR is implemented and tested
(skeleton, structs/pointers/arrays, switch, defer/errdefer, optionals,
error unions, minimal slices), and what remains (comptime/generics,
record-ABI shapes, std breadth) needs shared machinery, not more zparser.
