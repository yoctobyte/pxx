---
prio: 55
---

# Track T: gcc c-torture `execute/` runner — corpus rung above c-testsuite

- **Type:** feature (test tooling) — **Track T** (owns runners/fuzzers/corpus
  harnesses). Split out of [[feature-c-corpus-expansion]] on user direction
  2026-07-14: Track A started building this and was correctly stopped — the
  TOOL belongs to T; the bugs it finds go to A/C as usual.
- **Status:** backlog — DESIGN + BASELINE ALREADY MEASURED (see below); a
  working draft existed in a Track A working tree and was reverted, so this is
  re-implementation from a proven recipe, not exploration.

## What it is

gcc 14.2.0's `gcc/testsuite/gcc.c-torture/execute/` = **1656 self-checking
single-file C programs** (each calls `abort()` on a wrong result and exits 0 on
success — no .expected files, no output compare, oracle-free). The natural
conformance rung above the (long green, 220/220) c-testsuite.

## Proven recipe (all of this ran on 2026-07-14)

1. **Vendoring** — add `fetch_gcc_torture` to `tools/install_lib_candidates.sh`:
   blob-filtered sparse fetch (`git fetch --depth 1 --filter=blob:none` +
   `sparse-checkout set --no-cone gcc/testsuite/gcc.c-torture/execute COPYING`)
   of commit `c035a7c30c310ff928988cbcf445f3f21be10aa1` (releases/gcc-14.2.0)
   from https://github.com/gcc-mirror/gcc into
   `library_candidates/gcc-torture/execute/` + PROVENANCE.md (GPL — test DATA
   only, gitignored, never linked/shipped). Verified: 1656 .c files, small
   download thanks to the blob filter.
2. **Runner** — `tools/run_c_torture.sh`, a near-clone of
   `tools/run_c_conformance.sh` with the output-compare dropped (exit 0 = pass)
   and per-test timeout 15s: same positional compiler/suite args, same
   `--shard I/N` (testmgr fanout ready), same `--target ARCH` cross hook, same
   explicit `test/c-torture/pxx.skip` ("NNN.c<TAB>reason", plus
   `pxx.skip.ARCH` overlays).
3. **Ratchet skip file** — first run stands at **873 pass / 783 fail / 1656**.
   Seed `pxx.skip` with every baseline failure, one line each, categorized
   mechanically from the runner log:
   - `compile: <first error line>` — mostly GNU-extension/dialect gaps
     (nested functions, `__builtin_*`, vector/SIMD, `_Complex`, VLA, alloca,
     `__alignof__`, computed goto, wide char). ~700 entries.
   - `runtime: abort()` (exit 134) / `SIGSEGV` (139) / `timeout` (124) —
     **REAL-BUG candidates**, ~50-80 entries: these COMPILE silently and
     misbehave, exactly the class csmith keeps proving productive.
   Green then means "no NEW regressions vs baseline"; removing a line re-arms
   a test. Same model c-testsuite used to go 172 → 220.
4. **Makefile** — `test-c-torture` target invoking the runner; NOT wired into
   default gates/tiers initially (discovery corpus; T decides tier placement).

## Why T should want it

- The ~50-80 runtime-failure entries are a pre-triaged miscompile queue for
  spare-cycle fuzz-adjacent work: each is a tiny, self-checking, gcc-blessed
  repro. File findings per lane as usual (IR/codegen → A, cfront → C).
- `--shard` support means testmgr can fan the 1656 out like the conformance
  battery.

## Acceptance

- `tools/install_lib_candidates.sh gcc-torture` vendors the corpus.
- `tools/run_c_torture.sh` green against the seeded baseline skip file.
- Baseline numbers + skip-file categories recorded here.
- At least the runtime-failure entries triaged into a first batch of owning-
  lane tickets (or one cluster ticket per family, csmith-style).
