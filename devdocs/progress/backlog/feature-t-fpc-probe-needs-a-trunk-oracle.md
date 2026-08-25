---
track: T
prio: 50
type: feature
blocked-by: []
summary: "Every FPC-parity finding we produce is measured against installed FPC 3.2.2, so it inherits 3.2.2's bugs — and that has now twice produced a false 'pxx diverges from FPC' where pxx actually agreed with FPC trunk and only 3.2.2 was wrong. Give the probes a three-way verdict: pxx vs FPC-stable vs FPC-trunk."
---

# The FPC probes need a trunk oracle, not just installed stable

- **Type:** feature (test infrastructure) — **Track T** (`tools/fpc_diff_probe.sh`,
  `devdocs/dev/differential-probes.md`). T owns the tool; any compiler bug this
  surfaces still goes to the owning lane.
- **Opened:** 2026-08-16, at the user's observation:
  *"this is the second time we found a bug in fpc stable, that was already fixed
  in nightly."*

## The systemic cause

`tools/fpc_diff_probe.sh:60` invokes bare `fpc` — on this box, **FPC 3.2.2**,
released 2021. Every FPC-parity verdict the harness produces is therefore
"pxx vs a four-year-old stable", and a divergence caused by an FPC bug that
upstream has since fixed is indistinguishable from a divergence caused by pxx.

That is not hypothetical; it is the observed failure mode, twice.

## The worked case

[[decide-forin-mixed-int-float-ctor-vs-fpc]]. `for d in [1, 2.5]` measured
against 3.2.2 looked like a compat decision — match the reference or keep the
right answer — and reached Track U as a design fork with three options. Measured
against **trunk 3.3.1** (built 2026-08-16, tip `6c61f17e04`), all ten rows match
pxx exactly. There was never a divergence: 3.2.2 was reading uninitialised
memory (`for d in [1.5, 2, 3]` after a four-float loop printed values from the
*previous* array), and upstream had already fixed it.

Cost of not knowing: a decide ticket, a "DELIBERATE DIVERGENCE" comment in
`test/test_forin_nonordinal_array_ctor.pas` that was not one, and a
nearly-filed upstream bug report against an already-fixed bug.

## What to build

**A three-way verdict rather than a two-way diff.** With `pxx`, `fpc-stable` and
`fpc-trunk` outputs, every case classifies itself and the classification is the
useful part:

| pxx | stable | trunk | verdict |
| --- | --- | --- | --- |
| A | A | A | agree — no finding |
| **B** | A | A | **pxx divergence** — a real finding, ours to own |
| **A** | B | **A** | **FPC stable bug, fixed upstream** — a footnote about 3.2.2, NOT a divergence |
| **A** | B | **B** | **FPC bug still live** — report it upstream (see below) |
| A | A | B | an upstream regression, or a deliberate upstream change — look |

Rows 3 and 4 are the ones the harness cannot currently express, and they are
exactly the two the user cares about telling apart.

Suggested shape, in rough order of value:

1. **`FPC=` / `FPC_TRUNK=` env overrides** in `fpc_diff_probe.sh` — the minimum,
   and it unblocks manual re-checks immediately.
2. **Trunk run is opt-in, not default.** Keep the fast path fast; a `--trunk`
   flag (or "only when a divergence is found") means the expensive third oracle
   runs on the handful of cases that need it rather than the whole corpus.
3. **A persistent trunk oracle on this box.** Currently there is none — trunk
   was built into a session scratchpad and is gone. Needs a decision on where it
   lives and how often it is refreshed; a stale trunk build reintroduces the
   same problem one release later. **Ask the user before installing anything
   into `~`.**

## The build recipe (measured working, 2026-08-16, ~4 min)

```sh
git clone -s -n ~/src/fpc-source fpc-main && cd fpc-main
git remote add gl https://gitlab.com/freepascal.org/fpc/source.git
git fetch --depth=200 gl main && git checkout gl/main
make -C compiler -j$(nproc) ppcx64 FPC=/usr/bin/ppcx64      # -> FPC 3.3.1
make -C rtl      -j$(nproc)        PP=$PWD/compiler/ppcx64  # NOTE: PP=, not FPC=
./compiler/ppcx64 -Frtl/units/x86_64-linux prog.pas
```

Two traps worth encoding in the tool so nobody rediscovers them:

- **`make -C rtl FPC=<new>` silently builds the RTL with the INSTALLED compiler.**
  The only symptom is `PPU Invalid Version 207 expecting 208` at use time. The
  RTL makefile wants **`PP=`**.
- Whole-tree `make compiler` fails in `utils_all` with "Can't find unit system";
  `make -C compiler ppcx64` is all an oracle needs.
- `~/src/fpc-source` is the user's checkout, detached at `release_3_2_2`. Clone
  **from** it (`-s` is fast and shares objects); never build in it or move its
  HEAD.

Also: check the remote tip with `%cd`, not `%ad`. FPC's trunk tip showed author
date 2025-01-23 and commit date 2026-08-15, and the local mirror's `origin/main`
was 247 commits stale — reading that stale mirror's diff is what produced the
first, wrong "no fix found in trunk" conclusion.

## The policy this serves

Two rules the user set, which the harness should make cheap to follow rather
than leaving to whoever is triaging:

1. **Strict mode emulates FPC's behaviour, never FPC's bugs**
   ([[meta-dialect-extensions-and-fpc-strict]] § "The BOUNDARY of aim 2"). A
   verdict-row-3 finding must never reach the deliberate-divergence index.
2. **If it is still broken in nightly, report it upstream.** Being a good
   citizen is the stated intent; the harness knowing row 3 from row 4 is what
   makes that actionable instead of a manual investigation each time.

## Gate

`tools/testmgr.py --tier full` green (T's own gate for tooling changes), plus
the harness reproducing the worked case above: `for d in [1, 2.5]` classifies as
row 3 (FPC stable bug, fixed upstream) and not as a pxx divergence.

## Priority calibration (user, 2026-08-16) — dropped 45 → 25

> "don't worry. finding bugs in FPC is quite rare.. and their stable years old.
> plus, i bet people over there are also using fuzzing and agentic coding to
> improve the codebase. just, it's not impossible that we do find a new bug
> since, well, very related project in a way." — user

So the expected yield is low and this is convenience infrastructure, not a
correctness gate. Two consequences for whoever builds it: keep it **cheap and
opt-in** (item 2 above is the important one — do not run a third oracle across
the corpus), and do not let it grow into a standing trunk-tracking obligation.
The manual recipe below is sufficient for the once-or-twice-a-year case; the
`FPC=` / `FPC_TRUNK=` overrides (item 1) capture most of the value on their own.

Worth keeping in view, though: pxx and FPC are close enough in problem domain
that a genuinely NEW upstream bug is plausible, and that is the case where
reporting it upstream matters.
