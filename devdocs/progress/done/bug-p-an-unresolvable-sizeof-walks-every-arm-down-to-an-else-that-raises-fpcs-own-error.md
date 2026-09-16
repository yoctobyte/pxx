---
slug: bug-p-an-unresolvable-sizeof-walks-every-arm-down-to-an-else-that-raises-fpcs-own-error
title: "An unresolvable `{$if sizeof(X)}` takes the `{$else}` arm, which in FPC's own source is `{$error}`"
track: P
prio: 55
type: bug
status: done
owner: ""
found-by: frankb-56
created: 2026-09-16
tags: [conditional-directives, lexer, fpc-corpus, sizeof]
blocked-by: []
summary: "FIXED 2026-09-16. FPC ncon.pas:968 is `{$if sizeof(tcompilerwidechar)=2}` / `{$elseif =4}` / `{$else} {$error}`. The PRE-PASS cannot resolve a sizeof whose type is one unit further than the directive, an unresolvable {$if} answers False, so every arm tests false, control reaches the `{$else}` and the PRE-PASS raised FPC's own {$error} and halted -- which PasCondQuiet's own contract forbids in its declaration: \"it must not HALT there either -- the real pass is the authority\". Fix: {$error} is gated on the pre-pass. The real pass resolves the same ladder correctly, measured. REPRODUCED in three files / twenty lines once the missing variable was found -- the type must be ONE UNIT FURTHER than the directive; with it in the same unit the ladder already answered correctly, which is why the first three reductions all came back green."
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

## FIXED 2026-09-16 (frankb-56) — and this ticket's own hypothesis was WRONG

Filed hours earlier by me with "the reduction does not reproduce" and a
probe-nesting hypothesis. Both halves needed correcting, and the correction came
from one more probe rather than from more thought.

**IT REPRODUCES. The missing variable was a THIRD LEVEL**, twenty lines:

| | |
| --- | --- |
| `prepasserr_base` | `type tprepasswidechar = word;` |
| `prepasserr_mid` | `uses prepasserr_base` + the `{$if sizeof}` / `{$elseif}` / `{$else} {$error}` ladder |
| program | `uses prepasserr_mid` |

fpc 3.2.2 answers 2; pxx raised `Unsupported tprepasswidechar size`. **Move the
type into `prepasserr_mid` and the same ladder answers correctly** — that is
why all three of the original reductions came back green: every one of them had
the type within one hop.

**THE STATED MECHANISM WAS WRONG IN A CHECKABLE WAY.** This ticket said an
unresolvable sizeof "answers 0, and 0 is neither 2 nor 4". Probed directly —
`{$if sizeof(tprepasswidechar) = 0}` — it takes the ELSE arm too. So it does not
answer 0 and no comparison happens at all: `PasCondUnresolved` turns the WHOLE
expression False, and False for every arm is what walks control to the
`{$else}`. The distinction matters for the fix: nothing is wrong with the
arithmetic, and a fixture asserting `= 0` would have pinned the wrong mechanism.

**THE FIX IS THE FILE'S OWN CONTRACT, NOT A NEW RULE.** `PasCondQuiet`'s
declaration already says the pre-pass "must not HALT there either -- the real
pass is the authority and will raise the error itself", and its RESIDUAL
paragraph predicted this exact class while naming the tell as an INCLUDE inside
such an arm. An `{$error}` is the same residual through a louder door. `{$error}`
is now gated on `PasCondQuiet`; the real pass evaluates the same text and raises
it with a position.

**THE CONTROL GUARDS THE WORSE DIRECTION.** Swallowing a real `{$error}` would
be a worse defect than the false halt, since the directive exists to stop a
build. Asserted as a must-not-compile row that also checks the message survives.
And the fixture is a guard rather than a decoration: the PINNED compiler refuses
it with `Unsupported tprepasswidechar size`.

**CORPUS EFFECT, and it is forward progress rather than a unit.** nld now
advances past this wall to `conditional directive: the right operand of 'in' is
not a set constant this pass can read: 'supported_optimizerswitches'` — which is
the documented decline of the `in`-over-a-set work, its nested cross-unit term
limit. A LOUD decline in place of a wrong branch that read like a true statement
about the program. ncnv is unchanged at `TDoubleRec`.

Gate: `gate.sh quick` GREEN. Byte-identical to fpc 3.2.2.

## Log
- 2026-09-16 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
