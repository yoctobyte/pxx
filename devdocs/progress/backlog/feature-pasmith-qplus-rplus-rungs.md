---
summary: "pasmith rungs for {$Q+}/{$R+}: generate checked regions + try/except EIntOverflow/ERangeError harnesses, differential vs FPC"
type: feature
prio: 30
track: T
---

# pasmith: fuzz the {$Q+}/{$R+} check machinery

- **Type:** feature (fuzz grammar — Track T owns the tool).
- **Opened:** 2026-07-15, after the night that landed both features
  ([[feature-pascal-overflow-checks-q-plus]] slices all-hosted-targets,
  [[feature-pascal-range-checks-r-plus]] slices 1-5).

## Why

The checks were hand-oracle-verified shape by shape, and TWICE the ticket's
assumed semantics were wrong until probed (FPC does NOT check Abs/Sqr or
subword ops). A generator that sprinkles {$Q+}/{$R+}/{$Q-}/{$R-} regions
over its existing arithmetic/array/subrange rungs and counts caught
EIntOverflow/ERangeError per checkpoint would differentially pin the whole
semantic surface against FPC — including the statement-anchor timing rule
(trange4) that a directive between RHS and statement end must not
retro-apply.

## Sketch

- New knob `--checks N`: with probability derived from N, wrap a statement
  run in `{$Q+}`/`{$R+}` (and matching try/except counting per class).
- The checksum mixes the caught-counts, so a divergence localizes like any
  other checkpoint.
- Needs pasmith's exception rung (already exists: --excepts).
