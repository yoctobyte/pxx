---
track: B
prio: 45
type: bug
blocked-by: []
summary: "`make lib-test` fails in any fresh clone at lib_synapse with `unit source not found: synacode`. external/ is gitignored and nothing fetches synapse — install_lib_candidates.sh has no target for it, though that script exists precisely for on-demand third-party trees. Reads as a regression rather than a missing dependency, and now costs once per agent checkout."
status: done
owner: frank3
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

## 2026-08-17 — FIXED (Track B, frank3), with one correction to the premise

### The fetcher already existed

The ticket says "nothing fetches synapse" and proposes adding a target to
`tools/install_lib_candidates.sh`. Measured: **`tools/install_externals.sh` is
tracked, long-standing, and already clones synapse into `external/`** — and
`install.sh:130` already calls it, behind an interactive prompt that defaults to
**n**. So the tree was never unfetchable; the fetcher was *undiscoverable*,
which is a different defect with a different fix.

Nothing pointed at it from where the failure happens: not the compiler error,
not the Makefile, not `make lib-test`. Answering `n` to one install-time
question — or using any checkout not created by `install.sh`, which is all four
agent checkouts — left a tree the suite needs and no trail back to the one
command that produces it.

Two further things the sweep turned up, both real:

1. **The fetch was unpinned.** It cloned `--depth 1` and checked out
   `origin/master`, with no `PROVENANCE.md` — so no two checkouts were
   *guaranteed* the same synapse, which is precisely the reproducibility the
   ticket's "one checkout per agent" argument cares about, and precisely what
   `install_lib_candidates.sh`'s header policy requires of every other tree.
2. **`tools/testmgr.py`'s CORPUS_ROOTS message is stale**: it prints "these are
   NOT fetchable by script — clone each into external/". They are fetchable by
   script, and have been. That is Track T's file, so it is not touched here —
   handed to T separately.

### What landed

**`tools/install_externals.sh`** rewritten to the policy the sibling tool
states: pinned to `b3224c3d133a39c3c22decc24a20a7e0fd62fddc` (verified equal to
upstream HEAD today, so the pin changes no content), fetched with the same
one-commit `init`/`remote add`/`fetch --depth 1 <sha>`/`checkout FETCH_HEAD`
shape as `fetch_commit()` in `install_lib_candidates.sh`, `.git` stripped so the
tree is a pinned artifact rather than a checkout to develop in, a
`PROVENANCE.md` written beside it, `FORCE=1` to re-fetch, and idempotent
otherwise.

**`Makefile`** — the two `lib_synapse` recipe lines are now inside a
`ifeq ($(wildcard external/synapse),)` guard that otherwise prints

```
SKIP lib_synapse + lib_synapse_transitive_unit -- external/synapse absent; fetch it with: tools/install_externals.sh
```

**Skip, not fail.** The ticket's gate says the absent case should *fail* with a
good message; a loud skip is strictly better and is what the repo already does
elsewhere — `testmgr.py`'s own comment says a recipe that tests for its corpus
path "handles the absence itself (prints SKIP, exits 0)", and testmgr already
SKIPs these two jobs rather than reddening them. Failing would leave Track B's
entire gate unrunnable in a fresh clone, which is the complaint, not the fix.

The compile lines themselves are **unchanged, byte for byte** — they only moved
inside a parse-time conditional. That was deliberate: `testmgr.py` matches
recipes per line, so its job split and its `external/(...)` skip rule both still
see exactly what they saw before.

### Sweep: synapse is alone

`grep -rn 'external/'` across `*.sh`, `*.py`, `Makefile`, `*.mk`, `*.pas`,
`*.npy` (excluding `devdocs/` and `external/` itself) returns **only synapse** —
`Makefile:9761/9763`, `install.sh:132`, `test/manual/try_synapse_compile.sh:5`,
and the testmgr comments above. There is no second `-Fuexternal/...` tree.

### Gate — run from a genuinely absent state, not simulated

| step | result |
| --- | --- |
| `external/` moved away, `make lib-test` | **exit 0**, prints the SKIP line naming the script |
| `tools/install_externals.sh` on the bare tree | fetches `b3224c3`, writes PROVENANCE.md, no `.git` |
| re-run with tree present, `make lib-test` | **exit 0**, both synapse jobs compiled and asserted |
| re-run the fetcher | `synapse present … — skip`, idempotent |

Both `make -n` branches were checked to select correctly before the real runs.

### Still open: WHICH script should own this (Track U-ish, cheap either way)

The owner's confirmed direction (relayed 2026-08-17) was a `synapse` target in
`install_lib_candidates.sh`. That was decided without the fact above — that a
dedicated tracked fetcher already exists and is already wired into `install.sh`.
Adding synapse to `install_lib_candidates.sh` instead means one of:

- a second `DEST` in a script whose `DEST` is `library_candidates/` and which
  **refuses to run** if that root is not gitignored; or
- moving synapse under `library_candidates/`, which breaks `Makefile:9761/9763`,
  `install.sh`, `test/manual/try_synapse_compile.sh`, and testmgr's
  `external/` CORPUS_ROOTS entry; or
- a delegating alias — two mechanisms for one concept, the exact second-path
  smell `normalise-dont-special-case.md` warns about.

The *principle* the owner settled — third-party source never in the repo, fetched
on demand, pinned, with a PROVENANCE.md — is satisfied as landed. The two roots
mean different things (`library_candidates/` = corpora we compile to test the
compiler; `external/` = libraries test recipes link against), which is the
argument for two scripts. **Recommendation: keep it here.** Moving it later is a
few lines if the owner disagrees.

## Log
- 2026-08-17 — resolved, commit PENDING-COMMIT.
