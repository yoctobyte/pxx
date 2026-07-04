# Inline routine expansion (`inline;`)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-18 (design discussion — small-helper performance)

## Motivation

`inline;` is currently parsed and **accepted as a no-op** (see
[dialect/routines.md](../../dialect/routines.md)). PXX is single-pass with no
optimisation passes, so a call to a tiny helper pays full overhead:
prologue + epilogue + argument shuffle + `call` + `ret`. For small math/boolean
helpers (`Min`/`Max`/`Clamp`, bit twiddles, vector component ops) that overhead
dwarfs the actual work — often a 3-instruction body behind a ~5× call cost.
Honouring `inline;` for these is a real, broad performance win, especially in
hot loops and on embedded targets where every cycle counts.

## Approach — blunt and strict, at the IR level

Inline only `inline;`-marked routines that are clearly safe; otherwise emit a
normal call. **Never** silently miscompile and **never** hard-fail on an
ineligible body — degrade to a call and (optionally) warn.

- **Eligibility (v1):** free function/procedure (not a method first), single
  `Result` / no multiple exits, parameters and locals that are
  ordinal/pointer/float, **no managed locals/params** (string / dynarray /
  record with managed fields), **not recursive** (direct or mutual), body under
  a size cap.
- **Mechanism:** at IR construction/lowering, splice the callee IR into the call
  site — bind each argument to a fresh temp (evaluate once, preserve
  left-to-right order and side effects), rename callee locals to fresh slots,
  redirect `Result` to a caller temp, and translate the callee's single exit to
  a fall-through.
- **Ineligible →** compiler **warning** (`inline ignored: <reason>`) + normal
  call. Gate the warning so it is informative, not noise.

## Expectation setting

Without a constant-folding / peephole pass, inlining mainly removes call
overhead (no cross-boundary folding yet). That is still a large relative win on
tiny hot helpers. If a folding pass lands later, inline compounds with it.

## Scope boundaries (later slices)

- Methods / `Self` handling.
- Inlining routines that themselves call (non-leaf) under a depth budget.
- Inlining across units.
- A cost model / auto-inline of trivial routines even without the directive.

## Acceptance

- An `inline;`-marked eligible leaf helper emits **no `call`** at its use sites;
  the body is spliced with correct argument evaluation order and `Result`.
- An ineligible `inline;` routine compiles (warning + normal call), output
  unchanged vs. today.
- New oracle test exercising arg side-effect order, nested inline calls in one
  expression, and an ineligible case; `make test` green; `make cross-bootstrap`
  byte-identical on i386 + aarch64 + arm32.

## Update — greenlit + auto-inline scope (2026-07-03)

Part of the pin-time optimization campaign (see
[[feature-optimization-levels]], measured 2.04x codegen gap). Additions to
the original design:

- **Auto-inline (-O2)**: beyond honouring explicit `inline;`, auto-select
  candidates at -O2: leaf routines (no calls), body under a small IR-node
  budget (~12 nodes), no address-taken params/locals, not virtual/indirect/
  external/vararg, single return path. Explicit `inline;` keeps working at
  -O1; auto-inline is additive and silent (a `--warn-inline` diag can list
  decisions). The eligibility analysis (leaf/addr-taken/size) is the same
  scaffold [[feature-callconv-register-args]] needs — build it once.
- Self-host gate unchanged: -O0 byte-identical; inlining only under -O1+.

## Phase 0 MEASURED (2026-07-04) — opportunity sized

`--measure-inline` flag added (flag-gated, no codegen change): per compiled body
records IR-node count + leaf/early-exit/addr-taken-param facts; per direct
internal call target counts the call sites (`InlineMeasureBody` /
`InlineMeasureSummary` in ir_codegen.inc).

Measured on the compiler self-compile (30438 total direct call sites), leaf-only,
budget ≤12 IR nodes:

| Eligibility variant | procs | call sites |
|---|---|---|
| strict (single-exit + no addr-taken param) | 19 | 664 |
| relax early-exit | 19 | 664 |
| relax addr-taken | 21 | 670 |
| loose (leaf + size only) | 21 | 670 |

By budget (strict): @6 nodes → 617 sites; @12 → 664; @20 → 757.

Findings:
- **Strict eligibility captures ~99% of the leaf opportunity** (664/670). The
  single-exit and no-addr-taken-param restrictions cost almost nothing here —
  tiny leaf helpers rarely early-Exit or take a param's address. So v1 can be
  strict *and* safe with negligible loss.
- **~664 sites = 2.2% of all direct calls** — bounded, but concentrated on hot
  tiny helpers, each site saving a full call sequence (prologue/epilogue/arg
  shuffle/call/ret ≈ 6–8 instr). Comparable in magnitude to the regcall win
  ([[feature-callconv-register-args]] phase 1).
- The other ~97% of calls target NON-leaf or larger procs → needs depth-budget
  (non-leaf) inlining, a much larger effort. Deferred to a later slice.

Decision: implement v1 = explicit `inline;` + strict leaf auto-inline (-O2),
IR-splice at the call site. Both gated OptLevel>=2 (auto-inline could move to -O3
if we want explicit `inline;` at -O2 and auto at -O3 — user flagged this as an
option). Measure the actual self-compile delta after landing.
