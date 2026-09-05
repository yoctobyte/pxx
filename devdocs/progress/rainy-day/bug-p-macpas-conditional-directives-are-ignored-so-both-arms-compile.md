---
track: P
prio: 40
type: bug
blocked-by: []
summary: "PARKED IN rainy-day/ 2026-09-05 BY OWNER DECISION -- real, reproducible and intended-someday, not wrong and not unranked-because-unimportant. The MacPas conditional family (`{$setc}` `{$ifc}` `{$elsec}` `{$elifc}` `{$endc}` `{$definec}` `{$undefc}`) is unrecognised, so every one is ignored and BOTH arms compile; measured against fpc 3.2.2 `-Mmacpas`, which takes the correct arm. WHAT CHANGED IS THE RANKING, NOT THE MEASUREMENT: supported dialects are FPC and Delphi, other dialects deferred pending real code in active use (see decide-which-pascal-dialects-pxx-targets), and the 31549 `setc` occurrences behind this ticket are FPC\'s macOS bindings -- a count of text we do not intend to compile. THE DIALECT-AGNOSTIC HALF WAS NOT PARKED AND IS FIXED: `{$MODE MACPAS}` is now an ERROR, so this ticket's own repro stops at line 2 instead of compiling the arm it should never have entered. The measured harm recorded below is what sets that severity -- iso and extendedpascal only WARN, because no equivalent measurement exists for them. See decide-which-pascal-dialects-pxx-targets."
---

# MacPas conditional directives are ignored, so both arms compile

```pascal
program mp;
{$setc TARGET_X := 1}
{$ifc TARGET_X = 0}
  {$error this arm must not compile}
{$elsec}
{$endc}
begin writeln('mp ok'); end.
```

`fpc -Mmacpas` compiles this and prints `mp ok`. pxx warns twice about unknown
directives and then **reports the error inside the arm it should never have
entered**.

## Population

Directive words in fpc 3.2.2's own sources that pxx does not recognise, by
occurrence — this family is the whole top of that list:

| directive | occurrences |
| --- | --- |
| `setc` | 31549 |
| `ifc` | 6200 |
| `endc` | 6197 |
| `elsec` | 3682 |
| `elifc` | 1625 |
| `definec` | 237 |

Concentrated in the MacOS bindings (`univint`), which is also the code most
likely to be ported. Nothing else in that census exceeds single digits once the
string-literal artefacts are removed — FPC builds directive text by
concatenation in places (`'{$ifde'+'f ...'`), which a raw grep reports as a
directive word `ifde`; those are not real and are not counted here.

## Why "it warns now" is not enough

Compiling both arms is a wrong-program outcome, not a diagnostic gap. It happens
to fail loudly when the dead arm contains something invalid (as above), and that
is luck: two arms that are each independently valid — the common case for a
`{$ifc}` selecting between two constant definitions — compile into a duplicate
definition or a silently wrong constant.

## Why this is parked and not rejected

Owner decision, 2026-09-05: *"we target general fpc mode and even delphi mode,
for now that is enough, our goal is not to support every pascal language on this
planet, especially not if it's not in active use."* Explicitly **not never** —
which is why this is `rainy-day/` (real, intended, deferred) and not
`rejected/` (the report is wrong) or `low-prio/` (no plan, no claim).
Nothing in the measurement below is retracted. What is retracted is the
implication that 31549 occurrences ranks it.

## The ranking defect this ticket carried

The population table is a census of **fpc's corpus**, and a ticket sourced from a
corpus census inherits that corpus's priorities rather than ours. FPC ships
`univint` because FPC targets macOS. So the number is precise, was checked
carefully — the string-literal artefacts really were removed — and measures text
we have no intention of compiling. Precision on the wrong quantity reads as
authority. No program anyone wanted to build hit this; it was found by sweeping
for directive words, not by attempting a target.

The same sweep also produced a genuine finding (`{$A n}` reported as a typo:
ordinary Pascal, real code), so the instrument is not worthless — it cannot
rank. A census ticket with no program we want to compile behind it needs a
demand line or a lower prio.

## The fork, if it is ever picked up

Either implement the family (it is `{$ifdef}`/`{$if}` machinery under different
spellings, and `{$setc}`/`{$definec}` are `{$define}` with a value, which
`PasDefineValue` already carries), or make an unhandled *conditional* directive
a hard **error** rather than a warning — the same reasoning that made an
unfindable include a hard error in `bug-pascal-include-search-silent-miss`.
Ignoring a conditional is categorically different from ignoring a switch: a
switch changes how code is compiled, a conditional changes *which* code is.

Found by censusing fpc's corpus for directive words this compiler calls unknown,
after the unknown-directive warning landed — the census that also found `{$A n}`
being reported as a typo. See the ranking note above before quoting the table.

## Measured again 2026-09-05, with the mode line the ticket's repro omits

The repro above has no `{$MODE MACPAS}`, and real MacPas source does. Adding it
changes nothing — same two warnings, same error from inside the arm that should
never have been entered — because pxx's `{$MODE}` handler is
`DelphiMode := CaseEqual(name, 'delphi')` and everything else falls into one
bucket. That is the front door, and it is the half that is NOT parked -- it is fixed:
`{$MODE MACPAS}` now errors, naming this ticket's measurement as the reason, so
the repro above refuses at the mode line. What stays parked is IMPLEMENTING the
conditional family. The two are independent: the front door stops us building
the wrong program, and does not make us able to build the right one.
