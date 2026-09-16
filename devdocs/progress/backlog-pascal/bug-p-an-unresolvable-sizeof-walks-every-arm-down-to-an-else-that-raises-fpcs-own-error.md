---
slug: bug-p-an-unresolvable-sizeof-walks-every-arm-down-to-an-else-that-raises-fpcs-own-error
title: "An unresolvable `{$if sizeof(X)}` takes the `{$else}` arm, which in FPC's own source is `{$error}`"
track: P
prio: 55
type: bug
status: open
owner: ""
found-by: frankb-56
created: 2026-09-16
tags: [conditional-directives, lexer, fpc-corpus, sizeof]
blocked-by: []
summary: "FPC's ncon.pas:968 is `{$if sizeof(tcompilerwidechar)=2}` / `{$elseif =4}` / `{$else} {$error Unsupported tcompilerwidechar size}`. pxx lands in the `{$else}` and raises FPC's own error text; fpc compiles the unit, so we take an arm fpc does not — a WRONG BRANCH, not a refusal, which is the more expensive shape because the message reads like a real diagnostic about the program. Exposed (not caused) by the `in`-over-a-set fix, which removed the wall in front of it at nld.pas:2. THE REDUCTION DOES NOT REPRODUCE: `$elseif` works, a local alias sizes correctly, and a cross-unit alias in a used unit sizes correctly — all measured — so the cause is context-dependent. Leading hypothesis, UNCONFIRMED: probes do not nest (PasCondProbeUsedUnits refuses at ProbeDepth>0), so a sizeof needing its own probe from inside one declines, and under PasCondQuiet an unresolved expression answers False, which walks every arm to the `{$else}`."
---

## Why this is worse than a refusal

The sizeof door's own rule is that a name it cannot size is a DIAGNOSTIC, not a
default — its comment says so, and for the non-quiet path it is true: it raises
`sizeof cannot size this type here`. The pre-pass path is different. Under
`PasCondQuiet` an unresolved sizeof sets `PasCondUnresolved` and answers **0**,
and 0 is neither 2 nor 4, so every arm of a width ladder tests false and control
reaches the `{$else}`.

In ordinary source that arm is a fallback. In a compiler's source it is
routinely `{$error}` — the author's way of saying "this configuration is not
supported" — so the failure presents as a confident statement about an
unsupported width, and the reader goes looking at widths.

## What is measured, and what is not

Measured 2026-09-16 with `tools/fpc_compiler_corpus_probe.sh`:

- nld fails at `ncon.pas:3266` with `Unsupported tcompilerwidechar size`, which
  is FPC's own `{$error}` text (ncon.pas:968, symsym.pas:2800).
- `oracle-no=0` — fpc compiles the unit under the same flags.
- `tcompilerwidechar = word` is declared in **widestr.pas**, a different unit.

Measured and does NOT reproduce — three separate reductions, all green:

| probe | result |
| --- | --- |
| `$elseif` chain, local alias | `size 2`, matches fpc |
| `sizeof` of a local `= word` alias | correct |
| cross-unit `= word` alias in a `uses`d unit | `size 2`, matches fpc |

So the three obvious causes are all excluded and the remaining variable is the
CONTEXT the corpus probe creates, not the construct.

## The residual question, and who owns it

**"Not the construct" is half a finding.** The owner of "then what" is whoever
takes this: confirm or refute the probe-nesting hypothesis by instrumenting
whether `PasCondSizeOfNameOrAlias` is reached at `ProbeDepth > 0` for
`tcompilerwidechar`, and if so decide whether the pre-pass should answer a width
ladder at all — a directive it cannot evaluate arguably must not silently pick
the fallback arm. **Refusing to choose an arm is available and is probably
right**, since the non-quiet path already refuses.

Behind it sits [[feature-b-rtl-has-no-tdoublerec]] for ncnv, already p85.
