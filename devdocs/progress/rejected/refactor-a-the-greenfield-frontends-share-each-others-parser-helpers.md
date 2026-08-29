---
track: A
prio: 18
type: refactor
blocked-by: []
status: rejected
summary: "DUPLICATE of refactor-a-seven-frontends-borrow-rust-parser-helpers. Tombstone kept so citations resolve; the 123-places-in-zparser measurement and the substrate-doc framing were merged into the survivor."
owner: ""
---

# DUPLICATE — see `refactor-a-seven-frontends-borrow-rust-parser-helpers`

Same finding: the greenfield frontends call each other's parser support
functions, so `rparser.inc` cannot be omitted without breaking `zparser`,
`gparser`, `eparser` and `fparser`.

Nothing lost. Both measurements are in the survivor — **123 places in
`zparser.inc`** from this filing, **198 errors under `PXX_NO_RUST` across six
frontends** from that one — along with this ticket's framing against
`the-substrate-is-ast-and-ir-not-the-parser.md`.

Not deleted, per the tombstone convention: a stale reference should resolve to
something rather than to nothing.
