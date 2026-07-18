---
prio: 50
---

# FPC-compiler define profile (`fpcdefs.inc` build-config gates)

- **Type:** feature (compiler driver / per-library defines — Track A file
  ownership; consumed by Track P corpus work)
- **Status:** backlog — unclaimed
- **Opened:** 2026-07-18, out of the FPC-compiler gap analysis
- **Blocks:** [[goal-compile-fpc-compiler]] — second wall after
  [[feature-pascal-asmmode-directive-tolerance]]: every FPC compiler unit
  does `{$i fpcdefs.inc}`, whose branches are dead unless the build-time CPU
  defines are present.

## Problem

FPC's compiler is not standalone source; it is source **plus a build-config
define profile** injected by its makefile (`-dx86_64`, `-dcpu64bitalu`,
target defines, etc.). `--mimic-fpc` supplies the *language-ecosystem*
defines (`FPC`, `FPC_FULLVERSION`, `VER3_2_2`) but nothing supplies the
compiler-build profile, so `fpcdefs.inc` resolves to a nonsense
configuration and parsing dies shortly after the include.

## Fix shape

Reuse the Synapse per-library fine-grained-defines machinery: a defines
profile for "building FPC's compiler as x86-64-hosted, x86-64-target"
(`x86_64`, `cpu64bitalu`, + whatever fpcdefs.inc's include graph demands —
enumerate empirically by probing `cutils` → `cclasses` → upward). Deliver as
either a `--mimic-fpc-compiler` flag layering on `--mimic-fpc`, or a checked-
in defines file the corpus runner passes — prefer whichever the Synapse
pattern already made cheap. Document the chosen profile in the corpus dir.

## Gate

Track A driver change: `make test` + self-host byte-identical. Acceptance:
`cutils.pas` and `cclasses.pas` parse past `{$i fpcdefs.inc}` under the
profile (they may still hit later walls — those get their own tickets; see
the probe protocol in
`devdocs/progress/rainy-day/experiment-compile-fpc-as-stress-probe.md`).
