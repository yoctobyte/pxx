---
slug: decide-where-a-persistent-fpc-trunk-oracle-lives
track: U
type: decide
prio: 30
status: backlog
blocked-by: []
summary: "The FPC trunk oracle works but has nowhere to live: a trunk build is ~4 min and ~1GB, it must sit OUTSIDE the repo, and installing into ~ needs the owner's say-so. Three options with different refresh obligations. Filed because closing feature-t-fpc-probe-needs-a-trunk-oracle with item 3 undone would otherwise lose it."
---

# Where does a persistent FPC trunk oracle live, if anywhere?

- **Type:** decide — **Track U**. Opened 2026-08-26 by Track T, on resolving
  [[feature-t-fpc-probe-needs-a-trunk-oracle]].
- **Why it is here and not in T's queue:** the answer installs something into
  `~`, and that permission is the owner's. A coordinator dispatch is not owner
  authority, so T stopped at the repo boundary rather than guessing.

## What is already done, so this is not blocking anything

`tools/fpc_diff_probe.sh` takes `FPC=` / `FPC_TRUNK=` (each a full command line)
and classifies divergences three ways when a trunk oracle is supplied. **The
manual recipe works today** and captures most of the value on its own — the
ticket's own priority calibration says exactly that. This decision is about
whether the oracle stops being a thing someone rebuilds by hand.

## The fork

**A. Nothing persistent.** Keep the recipe in the ticket; whoever needs a
three-way verdict spends ~4 minutes building trunk into a scratch dir. Costs
nothing, and the expected yield is genuinely low — *"finding bugs in FPC is
quite rare"* (owner, 2026-08-16). The cost is that the classification is
available only to someone who already suspects they need it, which is the
opposite of when it helps: both false divergences were found by someone who did
**not** suspect the oracle.

**B. A build under `~` (e.g. `~/src/fpc-trunk`), refreshed on request.** What
the ticket sketched. Needs the owner's permission for the location, and carries
a standing obligation the ticket itself warns about: *a stale trunk build
reintroduces this problem one release later*. Trades one aging oracle for
another that ages more slowly.

**C. Build it on demand, cache it in the repo's ignored scratch.** No `~`, no
permission question, self-refreshing if keyed to the upstream tip. Costs ~1GB
of working tree and ~4 min on a cache miss, and needs a rule for when the cache
is stale. This is the option T would take if the choice were T's, because it has
no standing obligation and no owner-owned filesystem.

## What the owner is actually being asked

1. May anything be installed under `~` for this? (If no, C is the only option
   above A.)
2. Is the once-or-twice-a-year case worth any standing cost at all, or is A the
   honest answer given the stated yield?

**Recommendation: C if a persistent oracle is wanted, A if the yield estimate
still holds.** T's view is that the yield estimate is probably right and A is
defensible — but note the asymmetry that makes it a real question: the two
findings this would have caught were both found by someone who did not know to
look, and A only helps someone who does.

## Not to be confused with

The same permission question is open for a FreeBSD image (Track T,
`feature-t-freebsd-image-and-runner`). The coordinator is raising both with the
owner together so one answer covers the boundary for both; this ticket records
the FPC half so it survives its parent being resolved.
