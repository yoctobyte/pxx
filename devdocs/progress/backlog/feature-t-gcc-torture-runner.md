---
summary: "gcc c-torture: ONE-TIME harvest of the ~50-80 runtime-fail miscompile candidates — NOT a permanent runner (dropped: mostly dialect-gap skip-list busywork)"
type: feature
track: T
prio: 20
---

# gcc c-torture: one-time miscompile harvest (permanent runner dropped)

- **Type:** feature (test tooling) — **Track T** (owns runners/fuzzers/corpus). T
  owns the harvest; the bugs it finds go to A/C as usual.
- **Status:** backlog / icebox (prio 20). Do only if C-frontend bug-hunting becomes a
  priority — the corpus + recipe are one command away.

## Downscope decision (user, 2026-07-15)

The original ticket proposed a **permanent** `run_c_torture.sh` + a ratcheting
`pxx.skip` file + Makefile target + tier placement. Dropped. The baseline already
showed **~700 of 783 failures are GNU-extension / non-ISO-C dialect gaps** (nested
functions, `_Complex`, VLA, vectors, computed goto, `__builtin_*`) — things pxx may
never implement — so seeding and maintaining a 700-line skip-file ratchet is busywork.
csmith already covers random C differential; c-testsuite covers conformance. A third
*standing* C corpus with a maintenance tail is not worth it while the C frontend is
mature (tcc self-compiles; sqlite/lua/zlib pass).

**The one real asset is the ~50-80 runtime failures** (compile silently, then
abort/segv/timeout) — a pre-triaged, gcc-blessed, self-checking miscompile queue. That
value is captured by a **one-time harvest**, not a runner: run the execute suite once,
triage the runtime fails into owning-lane tickets, discard the dialect skips. No
skip-file, no tier, no maintenance.

## Corpus (already vendored)

`library_candidates/gcc-torture/execute/` — 1656 self-checking single-file C programs
(each `abort()`s on a wrong result, exits 0 on success; oracle-free). GPL test DATA
only, gitignored, never linked/shipped. Left in place by the reverted Track A draft.

## Harvest tool: `tools/c_torture_harvest.sh` (one-shot, NOT gated)

`bash tools/c_torture_harvest.sh [outdir]`. Compiles each program with
`pxx -Ilib/crtl/include -Ilib/crtl/src`; a COMPILE failure is a dialect gap (skip); a
compile HANG or nonzero RUN exit is a candidate. Candidates are cross-checked against
gcc and bucketed into `pxx_only.txt` (gcc passes → real pxx bug), `both_fail.txt`
(gcc also fails even with `-O2 -lm` → INVESTIGATE, never dropped), and
`feature_gap.txt` (program declares a `dg-options` flag pxx lacks). The gcc check
retries `-O2` and `-lm` before believing gcc fails — that recovers real bugs a naive
`gcc <f>` would hide (see the float-floor case below). NOT a runner, NOT wired into
any tier — a manual discovery tool.

## Results (2026-07-15 harvest, opus-trackT)

`scratchpad/torture_harvest.sh` over all **1656** execute programs
(`pxx -Ilib/crtl/include -Ilib/crtl/src`, 25s compile / 15s run timeouts):

- **875 pass**, **705 compile-fail** (GNU/dialect gaps — discarded, not bugs),
  **76 miscompile candidates** (compile OK, wrong runtime behavior).
- Cross-checked the 76 against a gcc oracle. **74 gcc passes → pxx-only miscompiles.**
  Of the 2 where gcc "also failed": **`float-floor.c` was a REAL pxx bug the oracle
  check nearly hid** — gcc's failure was a `-lm` link artifact at -O0 (`floor` needs
  libm; gcc -O2 folds it and passes), and pxx aborts because of
  [[bug-a-double-global-initializer-arithmetic-folds-to-zero]] (a global
  `double = 1024.0 - 1.0/32768.0` folds to 0.0). `eeprof-1.c` is a genuine feature
  gap (requires `-finstrument-functions`, which pxx lacks — gcc aborts without it too).
- **NET: 75 gcc-verified pxx-only bugs** (74 + float-floor).

### Methodology note — do NOT auto-dismiss "gcc also fails" (user, 2026-07-15)

The gcc oracle is a cross-check, **not ground truth**, and a "gcc also fails" result
is *more* intriguing, not a reason to drop:
1. the failure may be a harness artifact hiding a real pxx bug (float-floor: missing
   `-lm` at -O0) — always retry with `-O2` and `-lm` before concluding gcc fails;
2. both compilers may mishandle a well-defined program differently (a real pxx bug
   gcc happens to share, or a genuine gcc bug);
3. only a documented *feature requirement* the program itself declares (a `dg-options`
   flag pxx doesn't implement, like `-finstrument-functions`) is a legitimate drop.
Same principle pasmith already applies to its FPC oracle: earn the dismissal, never
reflex it. A "both fail" case is a THIRD bucket to investigate, never a silent discard.

**74 gcc-verified pxx-only miscompiles**, clustered by construct (the standing triage
queue — reproduce any with
`compiler/pascal26 -Ilib/crtl/include -Ilib/crtl/src library_candidates/gcc-torture/execute/<f> /tmp/x && /tmp/x`):

- **bitfield** (12): 20030714-1 20040629-1 990326-1 991118-1 bf64-1 bf-sign-2 bitfld-1
  bitfld-3 pr23324(compile-hang) pr34971 pr55750 pr57281(segv)
  → **FILED [[bug-c-bitfield-promotion-and-layout-cluster]]** (promotion to unsigned +
  the empty-union/odd-width layout hang). Worked exemplar for the rest.
- **64bit-int** (12): 20020201-1 20020510-1 20021127-1 20040705-1 20040705-2 20050316-1
  20050316-3 20060110-2 20071216-1 20080519-1(segv) pr39240 pr79121  → Track A (codegen)
- **float** (10): 20000731-1(timeout) 20031003-1 20050316-2 20060420-1 920710-1 920929-1
  packed-aligned postmod-1(segv) pr28982a pr28982b  → Track A (float codegen)
- **stdio/crtl** (6): 20040223-1 fprintf-1(segv) fprintf-chk-1 printf-1 printf-chk-1
  va-arg-21  → Track B (crtl) / cfront varargs
- **volatile** (5): 20030128-1 20040811-1 pr28289 pr43220 vla-dealloc-1  → Track A
- **packed/aligned** (3): 20041218-2 960117-1 pr23467  → Track A/C (struct layout)
- **complex** (2): 20020227-1 pr49644 · **switch** (1): medce-1 · **computedgoto/nested**
  (1): nestfunc-5 · **other** (22): 20000822-1 20001011-1 20001027-1 20010924-1
  20030105-1 20060929-1 20070919-1 20080604-1 20101011-1 970217-1 990222-1 pr22061-1
  pr23135 pr38048-2 pr42570 pr44164 pr56250 pr57568 scope-1 simd-1 simd-2 struct-ini-4

**Two compiler HANGS** (worst class — non-termination on valid input): `pr23324.c`
(in the bitfield ticket) and one more surfaced under the compile timeout — grep
`compile-hang` in the run.

Decision on the remaining families: recorded here as the triage queue rather than
filed as ~8 thin cluster stubs (per the "limit ticket noise" guidance). The bitfield
cluster is the worked exemplar; an owning-lane agent pulls the next family from this
list and files/fixes it the same way. Bump this ticket's prio if that should happen
proactively.

## Acceptance (downscoped)

- One harvest run recorded here: pass / dialect-gap / miscompile-candidate counts.
- The miscompile candidates triaged into owning-lane tickets (IR/codegen → A, cfront
  → C), csmith-style: one cluster ticket per family, not a pile of stubs.
- No permanent runner, skip-file, or tier wiring lands. If a future need arises,
  re-scope back up from git history — the original permanent-runner recipe is in the
  2026-07-14 revision.
