---
prio: 45  # auto
---

# Dynamic compiler tables — kill the fixed `array[0..MAX_*]` ceilings (+ dynarray dogfood)

- **Type:** feature (compiler architecture / capacity) — Track A
- **Status:** backlog
- **Owner:** unassigned
- **Opened:** 2026-06-27
- **Relation:** forced into view by [[feature-c-desktop-lua-sqlite-path]] M5 —
  sqlite's 257k-line amalgamation blew `MAX_TOKENS` (512K) and needed a bump to
  2M. Companion stress angle to managed-string / dynarray correctness.

## Problem

The compiler holds ~305 fixed parallel arrays `array[0..MAX_*-1]` in `defs.inc`.
Two costs:

1. **Hard ceilings.** Each `MAX_*` is a wall a big translation unit can hit
   (sqlite hit `MAX_TOKENS`; lua/sqlite will push `MAX_AST`, `MAX_IR`,
   `MAX_SYMS`, `MAX_UFIELD`, `MAX_CTYPEDEF`, `MAX_CPREP_*`, …). Each overflow is
   a manual bump + recompile + (because the bump changes the compiler's own bss)
   a stabilize/pin cycle.
2. **Static BSS bloat.** These tables dominate the compiler's ~165 MB bss. Most
   of it is reserved for worst-case inputs and never touched. Bumping a cap (e.g.
   512K→2M tokens, ×3 parallel arrays) quadruples that slice for every compile of
   every program, however small.

## Proposal

Convert the largest / most overflow-prone tables from fixed `array[0..MAX_*]` to
**dynamic arrays** that grow on demand (geometric, e.g. ×2 with an initial
modest reserve). Keep the `MAX_*` as a sanity hard-cap if wanted, but allocate
to fit.

### Priority candidates (biggest + most overflow-prone first)

- **Token tables** — `Tokens`, `TokPackRecords`, `CAttrFlags` (`MAX_TOKENS`, the
  one sqlite already broke). 3 parallel arrays, must grow together.
- `AST*` (`MAX_AST` 512K), `IR*` (`MAX_IR`), `Syms` (`MAX_SYMS`).
- C-frontend: `UField` (`MAX_UFIELD` 262144), `CTypedef*` (`MAX_CTYPEDEF`),
  `CPrep*` (`MAX_CPREP_PARAMS`/`MACROS`/`CHARS`).
- Output buffers `Code` (`MAX_CODE` 8 MB), `Data` (`MAX_DATA`).

Smaller bounded tables (`MAX_ARR_DIMS`, `MAX_CPREP_CONDS`, `MAX_GOTO_LABELS`, …)
can stay fixed — they are genuinely small and bounded.

## Bonus — dynarray correctness dogfood

The compiler is the densest dynamic-array user we have. If `Tokens[]` et al.
become managed dynarrays grown via `SetLength`, then **self-hosting exercises
dynarray growth/realloc on every compile**, across every backend, with the
byte-identical fixedpoint and the cross harness as oracles. Any latent bug in
dynarray grow / managed-element handling / cross-target dynarray ABI would
surface as a self-host or cross divergence. Free, brutal, deterministic coverage.

## Landmines

- **Parallel arrays must grow in lockstep** — `Tokens` / `TokPackRecords` /
  `CAttrFlags` are indexed by the same token id; a partial grow corrupts.
- **Indices/pointers held across a grow** — any code holding a raw element
  address (not index) over an append breaks when realloc moves the buffer. Audit
  for `@arr[i]` held across growth.
- **Self-host byte-identical must hold** — a tables refactor changes the
  compiler's bss/codegen; expect a multi-gen reseed (front-end-ish but touches
  hot paths) and re-pin. Validate on the self-hosted binary, not just FPC.
- **Cross + ESP** — dynarray growth goes through the managed-aggregate / RTL
  path; run the full cross harness. ESP (constrained RAM) actually *benefits*
  (no giant static reserve) but needs the managed-dynarray path working there.
- **Perf** — geometric growth amortizes, but a too-small initial reserve causes
  early realloc churn on big TUs; pick sane initial sizes.
- **Frozen vs managed self-build** — the compiler self-builds frozen; make sure
  the dynarray path is exercised in that mode too, not only managed user progs.

## Performance angle (2026-06-29)

Raised after the `make benchmark` run (commit `9eecff79` era):

- self-host pascal26 compiles `compiler.pas` **2.96× slower than FPC** (6.47s vs
  ~2.19s) — gap *widened* from ~2.1× as the compiler grew.
- managed-string hello is **23× slower** than frozen and yields a **110× bigger
  exe** (31.6 KB vs 287 B) — runtime memory/heap init dominates tiny programs.

User hypothesis: **the speed cost is largely memory management** — we reach for
fixed `array[0..MAX_*]` static storage where a grow-on-demand dynarray belongs,
and pay for it in a ~165 MB BSS that is touched/cache-thrashed and reserved
worst-case on every compile.

**Honest scoping (don't oversell):** the dominant self-compile lever is still
**register allocation** (no regalloc → ~2× baseline, per
[[project_make_test_timing_analysis]]) — converting tables to dynarrays will
*not* close the 2.96× gap on its own. Its perf wins are real but secondary:
smaller resident set / better cache locality / faster process startup (less BSS
to map+zero), plus killing the manual `MAX_*` bump+reseed treadmill. Treat perf
as a *bonus* on top of the capacity+RAM+dogfood case above, and **measure**
(wall-time self-compile + RSS + hello startup before/after) rather than assume.

## Execution constraint — do this on a dev branch, NOT master

This is a **big destabilizing overhaul** that touches the compiler's hottest
data structures. It breaks self-host byte-identical until it converges and needs
a multi-gen reseed + re-pin. Unlike the usual Track-A "work on master" rule, the
user has explicitly scoped this one to a **separate git dev tree / branch**:
land it incrementally there, get `make test` + self-host fixedpoint + full cross
+ ESP all green on the branch, *then* merge to master as one converged step.
Never carry a half-converted tables refactor on master (it would trip the
stable-binary / self-host gate for every other Track-A change).

## Acceptance

- Target tables are dynamic; compiler compiles sqlite (and lua) without manual
  `MAX_*` bumps for those tables.
- Compiler bss drops materially for small inputs (measure hello-world bss before/
  after).
- `make test` + self-host byte-identical (post-reseed) + cross (i386/arm32/
  aarch64/riscv32) + ESP build all green.
- A note in the ticket recording which tables were converted and which stayed
  fixed (and why).

## Log

- 2026-06-27 - Filed. MAX_TOKENS 512K→2M bump (sqlite M5) exposed the fixed-table
  ceiling pattern; user flagged the dynarray conversion as both the right fix and
  a self-host dynarray-correctness stress test. Future work — not blocking the
  sqlite arc (which proceeds on the static bump for now).
- 2026-06-27 - User decision: **static arrays are fine for now** (accept the RAM
  cost); dynarray conversion is explicitly **later**. Interim static bumps
  tracked in [[chore-sqlite-static-capacity-bumps]]. This ticket stays backlog as
  the eventual proper fix + dynarray dogfood.
- 2026-06-29 - Reframed with a **performance** motivation off the `make
  benchmark` numbers (pxx 2.96× slower self-compile; managed hello 23× slower /
  110× bigger). User hypothesis: speed cost is mostly memory management
  (static-over-dynarray). Added honest scoping (regalloc is the bigger lever;
  this is a secondary cache/startup/RAM win + dogfood) and an **execution
  constraint: do the overhaul on a dedicated git dev branch, not master**, then
  merge once converged. Still backlog, still not blocking anything.
