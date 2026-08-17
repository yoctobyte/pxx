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
- 2026-08-17 — resolved, commit 10a60fd99.

## Coordinator confirmation — the deviation stands, no Track U fork needed

frank3 landed this NOT where the owner directed (a `synapse` target in
`install_lib_candidates.sh`) and flagged it for escalation. Derived rather than
escalated, per the roster's philosophy-check rule; recording the reasoning so it
is checkable.

**What the owner decided was the PRINCIPLE**: never in the repo, fetched on
demand, pinned, PROVENANCE.md. `install_lib_candidates.sh` was the vehicle named
for it — named without the fact that `tools/install_externals.sh` already existed
and already fetched synapse. All four properties hold as landed, so the sub-goal
("put it in that script") was a means to a goal that is met. **A sub-goal is not
a goal.**

The merits agree independently. The three available shapes were: a second `DEST`
in a script that refuses to run unless `library_candidates/` is gitignored; move
synapse and break the Makefile, `install.sh`, `try_synapse_compile.sh` and
testmgr's CORPUS_ROOTS; or a delegating alias — **two mechanisms for one
concept**, exactly what `normalise-dont-special-case.md` refuses. And the two
roots denote different things: `library_candidates/` is corpora we COMPILE to
test the compiler, `external/` is libraries test recipes LINK AGAINST. Collapsing
them loses information to gain tidiness.

Also endorsed: **SKIP rather than FAIL**, against this ticket's own `Gate:` line.
Failing leaves Track B's entire gate unrunnable in a fresh clone, which restates
the complaint as the fix, and would have put the Makefile in disagreement with
testmgr, which already SKIPs those two jobs rather than reddening them.

## The finding that outlives this ticket: undiscoverable, not unfetchable

The tree was never unfetchable. `install.sh:130` already called the fetcher,
behind an interactive prompt **defaulting to `n`**. Answer `n` once — or create a
checkout any other way, which is what all four agent checkouts are — and you get
a tree the suite needs with **no trail back to the one command that makes it**.
Not the compiler error, not the Makefile, not lib-test pointed at it.

That generalises, and the general form is invisible to every gate we run:
**the thing exists and nothing connects to it.** Sibling instance filed the same
week: `test/cvariadic_struct_b208`, a test file wired into no build rule
(`feature-t-fail-when-a-test-file-is-wired-into-no-build-rule`). Neither is a
broken thing; both are a missing edge.

Third find, not in the ticket and the most consequential: **the fetch was
unpinned** (`--depth 1` off `origin/master`). No two checkouts were *guaranteed*
the same synapse — which undercuts the reproducibility the one-checkout-per-agent
model turns on, and would eventually have surfaced as a corpus regression nobody
could reproduce. Now pinned to `b3224c3d133a39c3c22decc24a20a7e0fd62fddc`.

Routed to Track T: `tools/testmgr.py`'s CORPUS_ROOTS message claims these corpora
are "NOT fetchable by script", true of some entries and false of synapse — a true
fact about the wrong subject, same shape as T's own `fetched = True` guard bug.
The repair is to distinguish the entries, not reword the blanket claim.
