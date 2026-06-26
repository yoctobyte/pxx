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
