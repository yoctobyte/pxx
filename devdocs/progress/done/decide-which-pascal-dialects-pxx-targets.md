---
slug: decide-which-pascal-dialects-pxx-targets
title: "Which Pascal dialects pxx targets: FPC and Delphi; the rest deferred pending real code in active use"
track: U
prio: 60
type: decide
blocked-by: []
status: decided
owner: ""
created: 2026-09-05
summary: "SETTLED BY THE OWNER 2026-09-05: supported dialects are general FPC mode and Delphi mode. Other Pascal dialects -- MacPas, ISO, Extended Pascal, Turbo/BP-only surfaces -- are DEFERRED, not refused: `rainy-day/`, revisited when real code in active use needs one. Recorded here rather than in the P backlog because two other populations hit it: the C frontend's own dialect surface, and anyone ranking a ticket produced by a corpus census. Scope, not a fork: it is written down so the next directive census does not re-file the same ticket at the same prio."
---

# Decided: FPC and Delphi. The rest is deferred, not refused.

Owner, 2026-09-05, verbatim:

> *"we target general fpc mode and even delphi mode, for now that is enough, our
> goal is not to support every pascal language on this planet, especially not if
> it's not in active use."*

**"Not in active use" is the test, and "for now" is load-bearing.** This is not a
refusal and it must not be written down as one. A dialect comes back the moment
there is real code someone wants to compile.

## What that means per folder

The four terminal folders say different things, and this decision picks exactly
one of them:

- **`rainy-day/`** — where a dialect-only gap goes. Real, reproducible,
  intended someday, deferred. First occupant:
  [[bug-p-macpas-conditional-directives-are-ignored-so-both-arms-compile]].
- **not `rejected/`** — that means the report is WRONG. These reports are right.
- **not `low-prio/`** — that means no plan and no claim. There is a plan; it is
  "when someone brings code".
- **not `known-incompat/`** — that is for a divergence we have CHOSEN and would
  defend. We have not chosen to miscompile MacPas; we have deferred supporting
  it.

## The part that is NOT deferred

**A dialect we do not support must be answered at the front door, and that is
dialect-agnostic work.** A MacPas program declares `{$MODE MACPAS}` several
lines before its first `{$ifc}`, so it announces at the top that we cannot
compile it. Erroring there is one check that says a true thing early; teaching
six conditional directives is dialect knowledge that says it late — and says it
only for the one dialect someone happened to census.

Measured 2026-09-05, before the fix: pxx accepted **every** `{$MODE}` silently.
The whole handler was `DelphiMode := CaseEqual(name, 'delphi')`
(`paslexer.inc`), so `MACPAS`, `ISO`, `EXTENDEDPASCAL` and `TOTALNONSENSE` all
fell into one bucket with no diagnostic. That is a different axis from the
2026-09-04 unknown-directive warning: that one keys on the directive NAME, and
this is a known directive with an unrecognised VALUE — measured, since
`{$TOTALLYUNKNOWNDIRECTIVE}` warned and `{$MODE TOTALNONSENSE}` was silent.

**Fixed the same day, and the SEVERITY IS SET BY EVIDENCE RATHER THAN BY THIS
POLICY** — which of the two questions applies is the thing to get right here,
because they are easy to conflate: *this record says which dialects we target*;
it does not say how badly each untargeted one goes wrong.

| `{$MODE …}` | | why |
| --- | --- | --- |
| `objfpc` `fpc` `tp` `delphi` `delphiunicode` `pxx` | accepted | the family we target; one superset dialect |
| `macpas` | **error** | measured harm: both arms of `{$ifc}` compile, wrong binary |
| `iso` `extendedpascal` | **warning** | no such measurement — see below |
| anything else | **error** | fpc 3.2.2 rejects it too, so it cannot be intent |

A first draft errored on all three unimplemented dialects and **the suite caught
it**: conformance row `tcase50` (`{ %NORUN }`, `{$mode ExtendedPascal}`, a
`case … otherwise`) COMPILES here and went red. Real code we build correctly,
refused on a harm nobody had demonstrated — which is exactly the narrowing
[[bug-p-a-spurious-unknown-directive-warning-cannot-fail-any-test-we-have]]
exists to warn about. Promote `iso` or `extendedpascal` to an error the day
someone measures a divergence, and cite the measurement at the check.

The accepted list is bounded by asking fpc rather than recalling it: fpc 3.2.2
has exactly eight modes and rejects everything else. A draft carried `turbo` as
an alias for `tp`, which is invented — `-Mturbo` is `Illegal parameter` and
`{$mode turbo}` is `Illegal compiler switch "TURBO"`.

## Why this record exists at all

Because a ticket sourced from a **corpus census inherits that corpus's
priorities, not ours.** The MacPas ticket carried "31549 occurrences of
`{$setc}`" — a careful, correct number, counting FPC's macOS bindings, which
FPC ships because FPC targets macOS. Nothing anyone wanted to build hit it. The
number was precise about the wrong quantity, and precision reads as authority,
which is how it sat at prio 40.

The same sweep also found a real defect (`{$A n}` reported as a typo — ordinary
Pascal, real code), so a census is a fine way to FIND things and not a way to
RANK them. **A census-sourced ticket needs a demand line — a program we want to
compile — or a lower prio.**

Without this record the next session to census directives re-files exactly that
ticket at exactly that prio, and re-derives this conversation.
