---
track: A
prio: 65
type: bug
status: urgent
owner: ""
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
