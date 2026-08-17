---
track: B
prio: 45
type: bug
blocked-by: []
summary: "`make lib-test` fails in any fresh clone at lib_synapse with `unit source not found: synacode`. external/ is gitignored and nothing fetches synapse — install_lib_candidates.sh has no target for it, though that script exists precisely for on-demand third-party trees. Reads as a regression rather than a missing dependency, and now costs once per agent checkout."
---

# `make lib-test` is unrunnable in a fresh clone — nothing fetches synapse

Found 2026-08-17 by the Track B session on a brand-new checkout
(`/home/rene/frank3`), which had to copy `external/` by hand from another
working tree to get its own lane's gate to run.

## Measured

- `.gitignore:29` ignores `external/`.
- `Makefile:9761` / `:9763` build `test/lib_synapse.pas` and
  `test/lib_synapse_transitive_unit.pas` with `-Fuexternal/synapse`.
- `grep -rn synapse tools/install_lib_candidates.sh` → **nothing**. No fetch
  rule anywhere.

So the tree references a path that the repo neither ships nor knows how to
obtain, and `make lib-test` — Track B's entire gate — dies partway with
`unit source not found: synacode`.

## Why this is worth fixing rather than documenting

The failure mode is the expensive kind: it does not say "missing dependency", it
says a unit is not found, partway through an otherwise-green suite. It reads as a
regression someone just introduced, which is exactly the wrong first hypothesis
and costs a bisect before anyone thinks to check whether the tree was ever there.

It has also just changed price. The session model is now **one checkout per
agent** (`frankonpiler`, `frank2`, `frank3`, `franktrackD`), so this is paid once
per agent rather than once per machine, and hand-copying `external/` between
working trees is a workaround that leaves no record of which revision anyone has.

## The fix, and why it is not "commit the tree"

`tools/install_lib_candidates.sh` exists for precisely this and says so in its
header: *"external/third-party source NEVER lives in the repo — only this tool
that installs it on demand"*, with each candidate pinned to an upstream
commit/version and given a `PROVENANCE.md`. Synapse simply never got a target.

So: add a `synapse` target to that script, pinned like the others, and make the
`lib_synapse` recipe fail with a message naming the script when the tree is
absent — rather than failing inside the compiler on a missing unit.

Check the same question for every other `-Fuexternal/...` in the Makefile while
in there; synapse is unlikely to be the only one, and the sweep is one grep.

## Gate

`make lib-test` green on a clone with no `external/` present, after running the
documented fetch step and not before; the absent-tree case fails with a message
that names the fix.
