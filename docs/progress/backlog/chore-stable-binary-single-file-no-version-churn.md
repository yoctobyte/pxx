# Stable binary: fixed-name overwrite (kill `vN` churn + the dangling-symlink trap)

- **Type:** chore (dev architecture / workflow) — Track A-adjacent (infra)
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-22
- **Priority:** low (not urgent) — but removes a recurring footgun.
- **Relation:** follows the v36 incident (commit d37d9fb) where the pinned
  symlink dangled. See [[feedback_pin_must_git_add_stable]],
  [[project_pinned_stable_builtin_isolation_fix]].

## Problem

`make pin` records each stable as a **new** file `stable_linux_amd64/default/vN`
and repoints the `pinned`/`latest` symlinks at it. Two costs:

1. **Working-tree churn / bloat.** Every pin adds a ~2.8 MB binary that lives in
   every checkout forever (`v1…v36` ≈ 100 MB and growing one-per-pin).
2. **Dangling-symlink trap.** A new `vN` is an *untracked* path, so
   `git commit -- stable_linux_amd64/` / `commit -am` silently skip it while still
   committing the modified `pinned -> vN` symlink. Origin then has a symlink to a
   missing file → Track B can't find the pinned binary. This bit **v36**
   (the `pinned` symlink was committed in 564f7d0, the `v36` blob only landed in
   the follow-up d37d9fb).

Note (sets expectations): git *history* size is unchanged by any renaming — each
distinct binary is one blob regardless of name. This ticket bounds the
**working tree** and removes the trap; it does not shrink history (that would be
LFS / out-of-band, a separate decision).

## Requirement (from the user)

- During active dev we only need the **latest stable** (and `latest` vs `pinned`
  for A's stabilize-without-blessing-B distinction). We do **not** need to keep
  old stable binaries around mid-dev.
- Permanent per-version retention is a **release** concern only — and releases
  already rebuild a fresh `pxx-<arch>` (`tools/release.sh`; `stable_linux_amd64/`
  is `export-ignore`), so they never depended on the `vN` history at all.

## Design (agreed) — keep the symlink, fix the target

- Keep `pinned` / `latest` as **symlinks** (path stability / convention; the dir
  `stable_linux_amd64/` is already platform-specific so unix-symlinks are fine).
- Point each symlink at a **fixed filename** that is overwritten in place, not a
  fresh `vN`:
  - `latest  -> stable_latest`   (overwritten by `make stabilize`)
  - `pinned  -> stable`          (overwritten by `make pin`, copy of stable_latest)
  - the symlinks are committed **once** and never change again.
- Because the binary is now a **modified tracked file** each pin (not a new
  untracked path), `git add -u stable_linux_amd64/` always stages it → the trap
  is structurally impossible.
- Keep `VERSION` (the integer) and extend it to also record the **source SHA**
  the stable was built from (provenance, since old blobs are no longer kept by
  name).
- One-time: retire the existing `v1 … v36` (see next section) so the working
  tree drops ~100 MB to ~5.6 MB (two binaries).

## Retiring the existing 36 versions — keep, searchable, un-littered

Requirement (user): don't lose them, keep them searchable, but stop them
cluttering the working tree. Plain `git rm` felt "blunt"; `git mv` to an archive
dir was floated.

**`git mv` to an in-tree archive does NOT help** — moved files still live in
every checkout (~100 MB unchanged). "Out of the tree" necessarily means they
leave the working tree. The non-blunt way:

- **`git rm stable_linux_amd64/default/v1 … v36` (one commit).** This does NOT
  destroy them — every `vN` blob stays in git **history** permanently
  (`git log --all -- <path>`, `git show <commit>:<path>`). "Keep" is satisfied;
  only the *working tree* sheds them.
- **Add a tiny text manifest** `stable_linux_amd64/STABLES.md` (a few KB, no
  binaries) so they are *searchable + one-command extractable*. One row per
  version:
  `vN | date | source-SHA | git blob hash | commit-where-it-lived`.
  Extract any old stable in one line:
  `git cat-file blob <bloghash> > /tmp/pxx-vN && chmod +x /tmp/pxx-vN`
  (or `git show <commit>:stable_linux_amd64/default/vN`). Generate the manifest
  from history before the `git rm` (`git log --diff-filter=A --format=... -- path`
  + `git rev-parse <commit>:<path>` for blob hashes).
- **Optional, only if you want them as one checkout-able set:** an orphan branch
  `stable-archive` holding the `vN` files, then `git rm` from `master`. Preserved,
  diff-free from master, fetched only on demand. Heavier; the manifest+history
  route already covers "keep + find + extract", so treat the orphan branch as a
  nice-to-have, not required.

This bounds the **working tree** only; git **history** still carries every blob
(unchanged by rm/mv — that's the LFS/out-of-band conversation, separate).

## Out of scope / non-goals

- **Releases unchanged** — they rebuild fresh; do not wire them to the dev stable.
- **Not** reducing git history size (that's LFS / publish-as-artifact — only do
  if pack growth ever actually hurts).
- Do **not** switch `pinned` from symlink to a plain file (the user wants the
  symlink kept).

## Implementation sketch

- `Makefile` `stabilize` target: write/overwrite `stable_latest` (instead of
  `vN++`); update `VERSION` (int + source SHA) + `history.log`.
- `Makefile` `pin` target: copy `stable_latest` -> `stable`; freeze
  `compiler/builtin/*.pas` into `stable_linux_amd64/default/builtin/` (unchanged);
  print the "git add -u stable_linux_amd64/ && commit" reminder.
- Ensure the one-time symlink repoint (`pinned -> stable`, `latest ->
  stable_latest`) is committed.
- Verify `make lib-test` (and `PXX_STABLE` resolution, `.../pinned`) still works.
- `make test` + self-host unaffected (no compiler change).

## Timing / coordination

Changing the symlink targets + `git rm` the old `vN` jostles Track B's ground
(the `pinned` file). **Do it in a quiet window**, not while B is mid-pull/build;
tell B to re-pull afterwards.

## Log
- 2026-06-22 — Filed after the v36 dangling-symlink incident. Design agreed with
  the user: keep the symlink, overwrite a fixed-name binary, drop `vN` churn.
  Pick up at a quiet coordination point.
