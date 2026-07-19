---
track: U
prio: 60
type: decide
---

# Where is the portable/per-target line drawn in the IR?

The one genuinely open fork in `devdocs/dev/type-identity-as-substrate.md`.
Blocks [[feature-a-abi-oracle]].

**The fork.** The IR must carry enough that backends stop reading `Syms[]`, but
NOT so much that per-target decisions get frozen into it and cross-compilation
breaks.

- **Option A — thin IR, fat oracle.** IR carries portable identity only
  (`TypeRef`). Every size/register/convention question is asked per-target at
  emit time. Maximum cross-target safety; the oracle is called a lot and
  backends get chattier.
- **Option B — lowered IR.** A per-target lowering pass rewrites the IR before
  emission, so decisions are already baked when a backend sees it. Backends get
  very simple; but the IR is then target-specific after that pass, which is a
  real change to what "the IR" means, and `optdiff`/cross-target differential
  testing would need rethinking.
- **Option C — hybrid.** Portable identity in the IR plus a small set of
  resolved FLAGS the middle can compute target-independently (e.g. "this is
  managed", "this needs finalisation"), leaving only genuinely ABI-shaped
  questions to the oracle.

**Recommendation: C.** It matches how `RetViaHiddenDest` already works
(one central predicate, consulted by every backend) which is the part of the
current design that did NOT rot — the return convention is the one rule with a
single authoritative site, and it has stayed consistent across all six backends
while the param rule drifted into 8 copies. Extending the thing that worked
beats inventing a new lowering stage.

Needs a human call because it decides what "the IR" means for every future
target, and `ir-as-substrate.md` is the north star it has to stay consistent
with.
