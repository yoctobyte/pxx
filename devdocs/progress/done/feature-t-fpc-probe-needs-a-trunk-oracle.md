---
track: T
prio: 50
type: feature
blocked-by: []
summary: "Every FPC-parity finding we produce is measured against installed FPC 3.2.2, so it inherits 3.2.2's bugs — and that has now twice produced a false 'pxx diverges from FPC' where pxx actually agreed with FPC trunk and only 3.2.2 was wrong. Give the probes a three-way verdict: pxx vs FPC-stable vs FPC-trunk."
status: done
owner: trackt-1
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

---

## Resolution (2026-08-26) — items 1 and 2 built; item 3 needs the owner

### What landed

**Item 1 — `FPC=` / `FPC_TRUNK=` overrides.** Both accept a **full command line**,
not a binary path. That is not generality for its own sake: a freshly built trunk
compiler needs `-Fu<its own RTL>`, and a path-only override would fail with `PPU
Invalid Version` — one of the two traps this ticket recorded — which reads as a
compiler bug rather than a configuration mistake.

**Item 2 — trunk consulted on untagged divergences only.** Never across the
corpus, per the cost constraint. A `known` / `bydesign` row was already
classified by a human; spending the expensive oracle there would spend it on the
rows that need it least. Guarded: the devtest asserts trunk invocations equal
the untagged-row count exactly, and zero for tagged rows.

**Item 3 — NOT done, and not mine to do.** A persistent trunk oracle installs
into `~`. This ticket says to ask the user first, and that permission cannot come
from a peer agent. The manual recipe below remains the path until the owner says
where a trunk build should live and how it gets refreshed — and the ticket's own
warning stands, that a stale trunk build reintroduces this problem one release
later.

### Two corrections to the design in this ticket

**The verdict table conflates an observation with a judgement.** It lists
`B|A|A` ("pxx divergence — ours to own") and `A|B|B` ("FPC bug still live") as
separate rows. They are the **same observation** — pxx differs from two FPCs
that agree — separated only by a view about who is *right*, which no output can
supply. Reporting them as distinct rows would mean the tool asserting a
correctness judgement it cannot make. So the implementation reports what is
actually visible: whether the two FPC versions agree with each other, and which
one pxx matches when they do not. FPC disagreeing with FPC is the fact worth
having, because it is proof the reference moved.

Implemented states:

| the two FPCs | pxx matches | row | counts as |
| --- | --- | --- | --- |
| agree | neither | `DIFF ... (trunk agrees with stable)` | divergence, run RED |
| disagree | trunk | `FPC-STABLE-BUG` | **not** a divergence, run GREEN |
| disagree | neither | `3-WAY` | needs a human, run RED |
| trunk cannot build it | — | `DIFF` + *"trunk cast no vote"* | divergence, run RED |

**Row `A|A|B` is structurally invisible, by consequence of item 2.** "Upstream
changed and pxx matches the OLD stable" cannot be seen when trunk is consulted
only on cases that already diverge — if pxx and stable agree, `probe()` returns
before trunk is reached. Seeing it needs the third oracle across the whole
corpus, which is exactly the cost that was ruled out. This is a real trade, not
an oversight, and it is stated in the script header so a clean run is read as
*"no divergence from stable, and what we found is classified"* and never as
*"we agree with trunk"*.

### The defect found on the way, which is worth more than the feature

The probe wrote to fixed paths — `/tmp/fdp.pas`, `/tmp/fdp_f`, `/tmp/fdp_p`,
`/tmp/fdp_c.log`. **Two copies running at once overwrite each other's source and
binaries, and the result is not a crash but a REPORT.** Measured 2026-08-26 when
the new devtest overlapped a live corpus run:

```
new divergences: 34   known/filed: 11   by design: 0   no-oracle skips: 90
DIFF        format-percent-and-exp fpc=[] pxx=[11|11<LF>10|10<LF>...]
```

`fpc=[]` is an oracle whose binary had been overwritten mid-run, presenting as
an oracle that **disagreed**. Both numbers are fiction. This is the torn-down-run
failure class — an incomplete run reporting in the vocabulary of a complete one —
in its worst location: the corruption arrives dressed as findings, in a tool
whose entire job is to be believed about findings. A run overlapping a sibling's
would have been triaged as 34 real parity bugs.

Fixed with `mktemp -d` + an EXIT trap. **Residual, stated in the header:** four
Pascal file-I/O probes still name fixed paths (`/tmp/fdp_io.txt` and friends)
inside their *quoted* heredocs. Unquoting those to inject `$WORK` would let `$`
sequences in the Pascal source expand instead, which is a worse trade; two
concurrent runs can still race on those four files.

Secondary consequence, and the reason this had to be fixed before anything else:
**a differential tool that cannot survive a second copy of itself cannot be
exercised by a devtest.** The guard below is only possible because of this fix.

### A process failure worth recording

The `/tmp` replacement was first done as a blind string substitution, which
turned `/tmp/fdp_file.txt` inside a Pascal literal into `"$WORK/f"e.txt`. That is
**rule 5 of `devdocs/dev/differential-probes.md`** — *never edit a probe by
slicing between markers* — broken in the same session, in the same file, while
adding rule 1b to that document. It was caught by reading the diff, not by a
test. Redone with replacements scoped to the harness block, and verified by
confirming no removed line touched a Pascal literal.

### Also fixed

A `3-WAY` row did not fail the run: the exit code keyed on `new` alone, so "we
match neither FPC" exited 0. Now `new + threeway`. `FPC-STABLE-BUG` stays
excluded — that row is a fact about 3.2.2, not about pxx.

The summary now always states the oracle's **reach**. `STABLE ONLY` says in
words what it cannot distinguish, because a two-way run and a three-way run that
found nothing are different facts and only one of them is worth much. A typo'd
`FPC_TRUNK` exits 2 rather than silently degrading to a two-way run — the worst
outcome being an operator who believes rows are classified when they are not.

### Docs

`devdocs/dev/differential-probes.md` gains **rule 1b: an oracle can be RIGHT and
still be OLD.** Rule 1 catches an oracle that looks broken; this is the one that
does not look broken at all.

## Log
- 2026-08-26 — resolved, commit PENDING-COMMIT.
