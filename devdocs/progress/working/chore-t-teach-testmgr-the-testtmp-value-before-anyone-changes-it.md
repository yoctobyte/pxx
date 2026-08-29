---
slug: chore-t-teach-testmgr-the-testtmp-value-before-anyone-changes-it
title: "Teach testmgr the TESTTMP value — four expressions hardcode the literal /tmp prefix and go blind at once if it moves"
track: T
type: chore
prio: 50
blocked-by: []
status: working
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
