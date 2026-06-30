# Meta: pxx dialect extensions ⟷ FPC compatibility (two aims, switch-guarded)

- **Type:** meta (governance / index / epic) — Track A
- **Status:** backlog (standing index — never "done"; new dialect work links here)
- **Owner:** — (Track A; language-design calls go to the user)
- **Opened:** 2026-06-30
- **Origin:** crystallised while designing the inline-var / auto-locals family
  ([[feature-inline-loop-var-rio]], [[feature-implicit-locals-sloppy-switch]]) —
  features bumped into by accident, but worth pursuing deliberately.

## The two aims (deliberately distinct)

pxx pursues **two goals at once**, and they pull in opposite directions:

1. **pxx's own dialect — lax, ergonomic, boilerplate-eliminating.** Type
   inference (`var x := expr`, the `auto` type), Delphi-10.3-Rio inline vars
   (`for var i := ...`), optional sloppy locals, forward-visible decl order, etc.
   This is *our* language; it may extend beyond standard Pascal where the design
   is good (Delphi set real precedents worth stealing).
2. **FPC compatibility — on request.** When asked (`--strict` / `--mimic-fpc`),
   pxx must compile standard FPC/Delphi-classic source and **reject** the pxx-only
   extensions, so FPC-targeted code stays portable and the cold FPC seed builds.

These are not in conflict **because they are guarded by switches.** Neither aim is
sacrificed: lenient is the productive default; strict is one flag away.

## The contract (rule for every dialect extension)

Any feature that diverges from standard FPC/Delphi-classic MUST:

1. **Be available by default** (lenient) *or* behind an explicit opt-in switch —
   never silently mandatory.
2. **Be disabled / rejected under the strict family** (`--strict` /
   `--mimic-fpc` / the relevant `{$...}` strict directive), so a strict compile is
   FPC-faithful. A dialect-only construct under strict must error with a clear
   "not valid in strict/FPC mode" message.
3. **Keep the self-build honest.** The compiler's own source must compile under
   the chosen default profile, and the strict path must stay reachable (so strict
   can become a profile without breaking bootstrap). Self-host byte-identical.
4. **Have a test on both sides** — the extension works in lax; the same source
   errors under strict.

A new dialect ticket should state, up front, *which switch guards it* and *what
strict does*.

## Index — dialect extensions (the lax aim)

**Shipped:**
- Type inference: inline `var x := expr` statement (`tyAuto`, default on,
  `--no-auto-var` off). The foundation; `var` without a type == `auto`.
- `for var i := a to b` — Rio inline loop counter (counted form).
  [[feature-inline-loop-var-rio]] (counted done; for-in inline remains).
- Forward-later-global opt-out: `--lax-decl-order` / `{$DECLORDER OFF}`
  ([[feature-implicit-identifier-binding-strictness-switch]]).

**Planned:**
- `for var x in coll` — Rio inline loop var, for-in form (element-type inference).
  [[feature-inline-loop-var-rio]].
- Implicit/sloppy locals (`i := 0` undeclared) behind `{$IMPLICITVARS}` /
  `--auto-locals`. [[feature-implicit-locals-sloppy-switch]].
- **Research more Delphi / modern-Pascal extensions deliberately** (inline `var`
  in any block, `var`-section inference, anonymous methods, etc.) — pick the
  good-design, forward-compatible ones. Future; file individually under this index.

## Index — FPC-strict / compatibility (the compat aim)

- `--mimic-fpc` / `{$MIMIC FPC}` — install the FPC define set
  ([[project_mimic_fpc_done]], done).
- `--strict` umbrella — [[feature-require-forward-strict-mode]].
- `{$DECLORDER ON}` (default) — declare-before-use gating, FPC-parity
  ([[feature-implicit-identifier-binding-strictness-switch]], done).
- `make test-fpc` / cold FPC seed — the compatibility gate (the compiler source
  stays FPC-buildable).

## Open governance question (for the user)

Should `--strict` be a single master switch that turns **all** dialect extensions
off at once (simplest mental model), or per-feature directives that `--strict`
merely *defaults* on? Recommendation: a master `--strict` / `--mimic-fpc` that
sets the strict default for every guarded extension, with per-feature `{$...}`
overrides for fine control. Decide before the second dialect feature lands so the
switch wiring is uniform.
