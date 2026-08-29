---
slug: chore-t-teach-testmgr-the-testtmp-value-before-anyone-changes-it
title: "Teach testmgr the TESTTMP value — four expressions hardcode the literal /tmp prefix and go blind at once if it moves"
track: T
type: chore
prio: 50
blocked-by: []
status: done
found: 2026-08-29
found-by: pxx-a5 (measuring bug-a-testtmp-defaults-to-a-path-every-checkout-shares)
owner: pxx-a5
---

# Teach testmgr the `TESTTMP` value

The prerequisite that makes
[[bug-a-testtmp-defaults-to-a-path-every-checkout-shares]] safe to act on. Filed
separately because it is **pure Track T** (`tools/testmgr.py`) while that one is
a Makefile change, and because the order matters: doing the Makefile half first
makes concurrency *worse*, silently.

## The constraint, already written down at the site

`make_dry_run()` carries four expressions that hardcode the literal `/tmp`
prefix as it appears in `make -n` output:

```python
tmp_re         = re.compile(r"/tmp/[A-Za-z0-9_./+-]+")
so_prod_re     = re.compile(r"-o\s+/tmp/\S+\.so\b")
loader_dir_re  = re.compile(r"LD_LIBRARY_PATH=/tmp(?![\w./-])")
TMP_RE         = re.compile(r"/tmp(?![\w.-])(?:/[A-Za-z0-9_.+-]+)*")
```

and a comment that is already the ticket:

> That is safe today and must stay a deliberate choice: […] `$(TESTTMP)`, whose
> default is `/tmp` precisely so this keeps matching. **If anything ever runs
> `make_dry_run()` with `TESTTMP` set elsewhere, all four go blind AT ONCE and
> fail silently** — no privatization (concurrent runs collide again) and no
> producer/consumer merge (which is how `test-core#555/#556` went red on
> 2026-07-12). **Teach them the value before setting it; do not set it and
> hope.**

## What "go blind" costs, in both directions

Both failures are silent and both produce a *verdict*, which is why this ranks
above the Makefile change it unblocks:

- **privatization lost** — `RUN_TMP` (`/tmp/testmgr-scratch-<pid>`) is applied
  by rewriting recipe text that matches `TMP_RE`. Text that no longer matches is
  not rewritten, so two runs share the path again. The rewrite exists because
  two runs "would interleave in each other's self-host chains and corrupt both"
  (observed 2026-07-08: a fixedpoint byte-diff on a clean tree).
- **producer/consumer merge lost** — the `.so` producer and the bare-`/tmp`
  `LD_LIBRARY_PATH` consumer are merged into one job because the loader finds
  the library by soname, sharing no filename. Unmerged, they land in different
  jobs with no ordering, which is `test-core#555/#556` red on a freshly booted
  box and green wherever a stale `/tmp/libspill.so` happened to survive.

## Shape

Derive all four expressions, and `RUN_TMP`, from one value read once
(`os.environ.get("TESTTMP", "/tmp")`), `re.escape`d. Note `RUN_TMP` must move
with it: privatizing into `/tmp/testmgr-scratch-<pid>` while the recipes write
to a different root would point the two halves at different files, which is the
same defect `pinned_tmp_paths()` exists to prevent one level down.

**Do not** simply broaden the regexes to match any path — the literal prefix is
what makes `pinned_tmp_paths()`'s "leave exactly these where they are" work, and
a looser match would privatize paths a compiled source has baked in.

## Gate

Track T's own, and it must be a real one: `tools/testmgr.py --tier quick` with
`TESTTMP` unset (byte-identical behaviour to today) **and** once with `TESTTMP`
set to a scratch dir, confirming privatization and the merge both still happen.
The second run is the whole point — a change that only passes with the variable
unset has tested nothing.

Guards in `tools/*devtest*.py` over `make_dry_run()`'s grouping for a synthetic
recipe set, both with and without the variable, so the merge is proven rather
than assumed.

## Why prio 50

Above the p55 ticket's own Makefile change in *order* though below it in
number: nothing should touch the default until this lands, and the p55 note now
says so. It is not urgent on its own — today's default is correct and the
comment is holding the line — but it is cheap and it converts a documented trap
into a guard, which is the same move `expect_same.sh` made this morning.

---

## 2026-08-29 — done. Thirteen sites, not four.

### The ticket under-counted its own subject

It named four expressions plus `RUN_TMP`. The grep found **thirteen** literal
`/tmp` sites in `testmgr.py`, and the work was not mechanical — each needed a
judgment about which of two classes it belongs to, and getting that wrong in
either direction is silent:

| class | sites | rule |
| --- | --- | --- |
| **follows `TESTTMP`** | `TMP_RE`, the three `make_dry_run` expressions, `_REASON_TMP_RE`, the pinned-path root, the rewrite's prefix slice, `RUN_TMP`, `reap_stale`'s scratch, both reaper globs, the FPC canary output | anything that matches or generates a path appearing in RECIPE text |
| **stays `/tmp`** | `/tmp/pxx-build-*`, `/tmp/tbench-*`, `/tmp/pasmith*`, `/tmp/pxx_c_conformance.*`, the private build dir | paths OTHER tools own and write themselves — they do not read `TESTTMP`, so following it here would make the reaper stop finding them |

The second class is the one a sweep would have got wrong. Following `TESTTMP`
there trades a silent collision for a silent leak.

`RUN_TMP` had to move with it, and that is not cosmetic: the privatized
destination must sit under the root the recipes name, or the rewrite points
producer and consumer at different files — the same defect `pinned_tmp_paths()`
exists to prevent one level down.

### Three of `make_dry_run`'s expressions were unreachable to a guard

They were function locals. Hoisted to module scope beside `TMP_RE`, which they
share a reason for existing with. **That is how four expressions came to encode
one assumption with only a comment holding them together** — a local cannot be
asserted about, so nothing could have caught one drifting.

### Verified in both directions, because one direction proves nothing

**Unset — byte-identical.** Every derived value equals the literal it replaced,
asserted against text written out longhand in the guard so it cannot drift with
the code it checks. This is the whole basis for landing the change: today does
not move.

**Set — they move together.** The "go blind AT ONCE" state is guarded as its
inverse: no derivation may still match the old root. One left behind is exactly
as bad as all of them, since privatization and the producer/consumer merge each
depend on their own regex matching.

### The gate this ticket demanded, run both ways

- `--tier quick`, `TESTTMP` unset: **GREEN**, 29/29.
- `--tier quick`, `TESTTMP=<scratch>`: **GREEN**, 29/29.

**The second run's scratch root was EMPTY afterwards, and a green with an empty
root proves nothing** — so it was not accepted as evidence. `rmtree(RUN_TMP)` at
`testmgr.py:968` explains it, but an explanation is not a measurement. The
direct proof instead:

```
TESTTMP=/tmp/ttproof  ->  make_dry_run('test-quick'):
    78 recipe lines naming the NEW root
     0 recipe lines naming a bare /tmp
    e.g. ./compiler/pascal26 test/quick_canary_nilpy.npy /tmp/ttproof/qc_nilpy26
```

So `make` honours the environment variable (`TESTTMP ?= /tmp` yields to it), the
recipes really do move, and the derived expressions are what match them.

### Guards

8 in `tools/testmgr_testtmp_devtest.py`, loading the module fresh under each
value. Four mutations, each `ast.parse`d and confirmed applied before its result
was read: one expression left behind (2 fired), `RUN_TMP` left behind (1),
root interpolated raw instead of `re.escape`d (1), normalisation removed (2).

The escaping guard earns its place — a root containing `+` would otherwise be a
quantifier, matching `/tmp/aab` for `/tmp/a+b`.

### What this does and does not unblock

It makes [[bug-a-testtmp-defaults-to-a-path-every-checkout-shares]] **safe to
act on**; it does not act on it. That remains a Track A one-liner. And it does
nothing at all for the runtime half —
[[chore-t-test-binaries-hardcode-unsweepable-tmp-paths]], 60 paths baked into
compiled sources across 37 files — which no default can reach.

## Log
- 2026-08-29 — resolved.
- 2026-08-29 — resolved, commit 10e405656.
