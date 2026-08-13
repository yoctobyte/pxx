---
track: D
prio: 40
type: docs
blocked-by: []
summary: "One row in docs/reference/cli.md for --fpc-float-errors (landed 2026-08-13): opt-in FPC float-error emulation. The default — quiet IEEE, inf/NaN propagate — is worth a sentence there too, since it is a deliberate divergence from FPC that a Pascal reader will not expect."
---

# Document `--fpc-float-errors` in the CLI reference

- **Type:** docs — **Track D** (`docs/reference/cli.md`)
- **Opened:** 2026-08-13, alongside [[feature-float-exception-mask-control]]
  slice 2, which added the flag but must not edit `docs/**`.

## The row

Next to `--no-div-check` / `--no-signals` in the options table:

| `--fpc-float-errors` | Emulate FPC's float error behaviour: unmask invalid / zero-divide / overflow at entry and report a trap as FPC's runtime error (208 float division by zero, 205 overflow, 207 invalid, 206 underflow). Off by default — pxx propagates `Inf`/`NaN` quietly. x86-64 only; needs the signal runtime (not with `--no-signals`). |

## Worth a sentence beyond the row

The DEFAULT is the surprising part for a Pascal reader, and it is a decision,
not an omission: `1.0/0.0` is `+Inf` and keeps going. The reasoning (user,
2026-07-02) is that real measurement/streaming data with out-of-bounds inputs is
better served by inf/NaN propagating through a computation than by aborting in
the middle of it. FPC unmasks at startup and pxx does not; this flag is how a
program asks for FPC's behaviour.

Verify the numbers by compiling the examples rather than copying them —
`test/test_fpc_float_errors.pas` is the source of truth and they were measured
against FPC 3.x.
