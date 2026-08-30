---
track: A
prio: 65
type: bug
status: done
owner: frankA
blocked-by: []
summary: "`make pin` correctly freezes `compiler/builtin/*.pas` into `stable_linux_amd64/default/builtin/`, but the hand-off line it prints is `git add -u stable_linux_amd64/` -- and `-u` stages only TRACKED files. A builtin unit added since the last pin is UNTRACKED in the stable tree, so it is frozen on disk, passes pin verify, and is then silently left out of the commit. Two such units exist right now: builtinentropy.pas and builtinwide.pas, both landed 2026-08-30."
---

# A pin that adds a builtin unit cannot commit it with `git add -u`

- **Type:** bug (Track A — the pin procedure). Found 2026-08-30 by frankB, from
  the consumer end; mechanism read by the coordinator.

## The state right now

```
compiler/builtin/                    stable_linux_amd64/default/builtin/
  builtin.pas                          builtin.pas
  builtinentropy.pas   <-- NEW           (absent)
  builtinheap.pas                      builtinheap.pas
  builtinwide.pas      <-- NEW           (absent)
  exceptions.pas                       exceptions.pas
  ... 7 more, all present ...           ... 7 more ...
```

`git ls-files stable_linux_amd64/default/builtin/` lists **nine** files. The live
tree has **eleven**. Both new units landed today — `builtinwide.pas` from step 7a
of the UTF-16 campaign, `builtinentropy.pas` from `ba14f5f56`.

## What is NOT the bug

**`make pin` handles the copy correctly.** Makefile ~16292:

```make
@rm -rf $(STABLE_DEFAULT_DIR)/builtin
@mkdir -p $(STABLE_DEFAULT_DIR)/builtin
@cp compiler/builtin/*.pas $(STABLE_DEFAULT_DIR)/builtin/
```

A glob, not a list — so a pin picks up new units automatically and nobody has to
remember. The stable tree is stale purely because **no pin has run since v396
(14:38Z)** and both units landed after it. That part is working as designed.

## The bug is the hand-off line

`make pin`'s last words are:

```
Hand to track B:  git add -u stable_linux_amd64/ && git commit ...
  (-u stages the in-place-overwritten stable_pinned/stable_latest; all stable
   files are tracked, so nothing can dangle.)
```

**`git add -u` stages modifications to TRACKED files only.** Its parenthetical is
a true statement with an expiry date: "all stable files are tracked" holds until
the moment a new builtin unit appears, which is exactly the pin where it matters.

So the sequence is: pin freezes eleven files on disk → `pin verify` compiles
`test/test_uses_sysutils.pas` against the frozen tree and **passes**, because the
files are there → `git add -u` stages nine → the commit blesses a stable tree that
is missing two units → the working checkout keeps working, because the compiler
falls back to CWD-relative `compiler/builtin/`.

**Every check in the chain passes and the artifact is still wrong.** The failure
is only visible to a consumer of `stable_linux_amd64/` *alone*: a release, a fresh
checkout of just that directory, or a build run from a tree with no `compiler/`.

Measured by frankB from `/tmp` with absolute paths, before the pin question was
even raised:

```
error: uses: unit source not found: builtinentropy
  in: /home/neo/frankB/lib/rtl/random.pas
```

## Fix

Change the printed hand-off to `git add -A stable_linux_amd64/` (or
`git add stable_linux_amd64/`), which stages additions and deletions as well as
modifications — `rm -rf` + `cp` means a *removed* builtin unit has the mirror
problem, and `-u` would catch that one while missing the addition.

Better still, have `make pin` do the `git add` itself rather than print advice:
the copy is already the Makefile's job, and the staging is the half that has no
glob protecting it.

## Why urgent rather than p65-in-backlog

The next pin taken without this fix commits a knowingly incomplete artifact while
holding the repo-wide lock, and nothing downstream reports it. The coordinator
runs pins; this must be read before the next one.

## The wider note frankB attached

`$(PXX_STABLE)` builds read `compiler/builtin/**` from the **working tree** via
the CWD-relative fallback, so Track B's ground is not the pinned binary alone.
That is how `ba14f5f56` reached Track B with no pin at all — convenient here, and
it means **a Track B green can move because Track A edited a builtin source, with
no pin and no notice.** Related: [[bug-pinned-stable-reads-live-builtin-rtl]],
which closed the other half of the same seam.


---

# FIXED — 2026-08-30, frankA

`make pin` now **stages the tree itself** instead of printing advice for a human
to retype. The fix is the ticket's own "better still": the copy was already the
Makefile's job, and the staging was the half with no glob protecting it.

```make
@if git rev-parse --git-dir >/dev/null 2>&1; then \
   git add -A -- $(STABLE_ROOT) || { echo "PIN STAGING FAILED ..."; exit 1; }; \
   ... prints the name-status of everything staged, then the commit line ...
 else echo "not a git repo -- nothing staged."; fi
```

`make revert` in the same Makefile already staged itself with `git add -A`, so
pin was the odd one out; this makes them agree rather than inventing a shape.

## Measured, both directions, in a scratch repo

A real `make pin` could not be the test — it moves the pin and holds the
repo-wide lock — so the exact recipe block was extracted from `make -n pin` and
run against a scratch repo reproducing the failure state: a freeze that **adds
two** units and **removes one**.

**Before** (`git add -u`), which is the baseline the fix has to beat:

```
D  stable/builtin/goingaway.pas          <- the removal, caught
                                         <- BOTH additions missing
```

**After** (`git add -A`), the same freeze:

```
M  stable_linux_amd64/default/VERSION
A  stable_linux_amd64/default/builtin/builtinentropy.pas
A  stable_linux_amd64/default/builtin/builtinwide.pas
D  stable_linux_amd64/default/builtin/goingaway.pas
M  stable_linux_amd64/default/stable_pinned
```

Committing that and counting what a consumer of the tree *alone* would get:
**4 tracked = 4 on disk.** The ticket's mirror claim holds exactly — `-u` caught
the deletion and missed both additions.

Confirmed `-A` is safe to switch to here: `stable_linux_amd64/` currently has
**zero** untracked and **zero** ignored files, so `-A` stages the pin's own
output and nothing else.

## Not fixed, because it is not this bug: the tree is still short two units

The stable tree on disk has 9 builtin sources and the live tree has 11. That is
not a staging failure — **no pin has run since v396**, so the freeze has not
happened yet. The fix is prospective and the next pin closes it. Deliberately
not patched by hand: copying sources into `stable_linux_amd64/` without pinning
the binary would produce an artifact whose sources and binary do not correspond,
which is a worse object than the one this ticket describes.

## `tools/testmgr.py --pin` — Track T's file, NOT edited, and it is not broken

It stages with a **pair**, and the pair happens to cover this bug:

```python
_git("add", "-u", STABLE_ROOT_REL)                    # tracked only
_git("add", STABLE_DEFAULT_REL + "/builtin")          # this one saves it
```

Plain `git add <dir>` stages additions and deletions inside that directory, so
`builtin/` is fully covered there. Verified rather than assumed — testmgr's exact
pair, run against a freeze that adds a builtin, drops a builtin, and adds a file
in a **sibling** directory:

```
A  .../builtin/builtinentropy.pas     staged
D  .../builtin/goingaway.pas          staged
M  .../stable_pinned                  staged
?? .../newdir/added.txt               LEFT UNTRACKED
```

So **testmgr --pin was never exposed to the reported bug**, and no fix is owed
there. What it does have is the same defect one level up: it is protected by a
**hardcoded path** rather than by a rule, so any future directory added under
the stable root repeats this exactly. Reported to Track T as an observation, not
filed as a bug — nothing is wrong today.

Gate: Makefile only, no compiler source touched; `make -n pin` parses and expands
correctly, and the recipe was executed against a scratch repo as above.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
