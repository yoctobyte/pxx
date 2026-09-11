---
slug: task-b-five-system-names-still-in-sysutils-are-waiting-on-a-pin-not-on-a-decision
track: B
type: task
prio: 30
status: open
found: 2026-09-09
found-by: frankS
owner: ""
blocked-by: []
summary: "ELEVEN names, not five, and the number changed because the SIX THAT MOVED CAME BACK as a deliberate duplicate on 2026-09-11. LowerCase, StrLen, StrPas, SysBackTraceStr and StringOfChar are still declared only in lib/rtl/sysutils.pas; AllocMem, DynArraySize, SetString, sLineBreak, UTF8Decode and UTF8Encode are now declared in BOTH sysutils.pas and compiler/builtin/builtin.pas. Nothing here is undecided: lib/rtl and every external corpus build with $(PXX_STABLE) against a FROZEN copy of compiler/builtin, so a name that lives only in builtin/ is invisible to them. Measured three times -- `undefined variable (LowerCase)` from inside sysutils.pas, `undefined variable (StringOfChar)` at lib_strpchar.pas:49, and on seven `undefined variable (SetString)` in external/synapse/synautil.pas plus `undefined variable (UTF8Encode)` in testjsondata.pp, which took out four tstate rows for two days. THE TRIGGER IS A PIN whose stable_linux_amd64/default/builtin/builtin.pas carries these names; grep it there, that is the whole test. Then move the five and DELETE the six duplicates from sysutils.pas. Do NOT start before that pin exists. `Error` is a twelfth name and is NOT part of this row: it is compiler-internal here and needs sysutils' exception hierarchy first."
---

# Eleven names are one pin away, and the blocker is mechanical

## What to do, once the trigger has fired

1. Confirm the trigger, and it is one grep, not a build:
   `grep SetString stable_linux_amd64/default/builtin/builtin.pas` must find it.
   **It finds nothing today.** Nothing about a pre-scan — the unit-level clause
   written for the first six was measured DEAD and removed at `0e2e8dc6b`.
   The behavioural form of the same control is a program that calls `LowerCase`
   with no `uses` under `stable_linux_amd64/default/pinned`; it must fail before
   the work starts, or the control is drawn from the wrong tree.
2. Move the five declarations and bodies from `lib/rtl/sysutils.pas` into
   `compiler/builtin/builtin.pas`, **and in the same change DELETE the six
   duplicates** (declaration and body) that this ticket's 2026-09-11 repair put
   back in `sysutils.pas`. Those two halves are one commit: the duplicate exists
   only to span a pin-era, and leaving it behind is how two homes for one
   routine becomes permanent rather than bounded.
3. Add each name to the pre-scan in `pasparser_prog.inc` — the call-shaped
   group, or the bare-name group for anything spelled without parentheses. A
   builtin that is declared and never dragged in answers `undefined variable`,
   which is the symptom being fixed. **ONE trigger, not two:** a unit-level
   clause was written for the first six and removed as dead code the same day
   (any `uses` clause already pulls `builtin`, and a unit is only ever compiled
   because a program `uses` it). Do not re-add one — see the note in
   `pasparser_proc.inc` where it used to be.
4. Extend the two fixtures rather than writing new ones —
   `test/test_b_system_names_reach_a_program_with_no_uses_clause.pas` (program
   half) and `test/units/uambientsys.pas` +
   `test/test_unit_ambient_system_surface.pas` (from-inside-a-unit half). **The
   program fixture is the one with a positive control**: it names the routines
   with no `uses` line at all, so it fails if the trigger is missing. The unit
   rows cannot fail for a missing pull and their header says so — do not read a
   green there as covering one.
5. `make lib-test` is the gate that matters here, not `make test` — it is the
   build that broke both times.

## The population to check before moving anything — and it has been wrong THREE TIMES

`grep` for each name across **everything the pinned build compiles.** That is
`lib/`, `examples/`, the `test/lib_` rows **and `external/`** — synapse, fpjson,
and whatever else `tools/install_externals.sh` and
`tools/install_lib_candidates.sh` fetch.

Each round widened the population by exactly one group it had not thought of:

| round | the group that was missed | how it announced itself |
| --- | --- | --- |
| 2026-09-09 | `lib/rtl` calling its own declarations | `undefined variable (LowerCase)` from inside `sysutils.pas`, every unit |
| 2026-09-09 | the `test/lib_` rows | `undefined variable (StringOfChar)` at `lib_strpchar.pas:49` |
| 2026-09-11 | `external/` | `undefined variable (SetString)` in `external/synapse/synautil.pas`; `undefined variable (UTF8Encode)` in `testjsondata.pp` |

**THE THIRD ROUND IS THE ONE THAT DOES NOT REPRODUCE LOCALLY, AND THAT IS THE
WHOLE POINT.** `external/` is absent on plexus, so the Makefile SKIPS the three
`lib_synapse` rows and `make lib-test` goes green having compiled a smaller
corpus. It says so on its own last line — `SKIPPED: synapse-ssl ... (green here
does NOT cover them)` — and that line is the instrument. **Read it before
clearing an RTL move**, or fetch the externals first
(`tools/install_externals.sh`) so there is nothing to skip.

The fourth round is not worth guessing at: when the pin lands, move all eleven
and re-run against a host that has `external/` present.

## Provenance

Split out of `task-b-nineteen-sysutils-names-that-fpc-keeps-in-system` so its
summary could be true — six of twelve landed, and the rest is not a smaller
version of the same question.

## 2026-09-11 — the six that moved came back, as a duplicate

Not a revert: `compiler/builtin/builtin.pas` keeps all six, and
`lib/rtl/sysutils.pas` got its six declarations and bodies back beside them. For
one pin-era that is the only shape correct on both sides of the cliff — code
compiled by HEAD reads builtin's copy, code compiled by `$(PXX_STABLE)` reads
sysutils'. It is bounded by construction: the retirement test is written on the
`sLineBreak` note in `sysutils.pas` and it is a grep, so nobody has to remember
the reasoning to undo it.

Two homes for one routine was named in the original commit as the defect class
this work set out to fix, so the duplicate is a genuine concession and is
recorded as one. What made it the right concession rather than a workaround:
**it is already the normal state for three names.** `FloatToStr`,
`FloatToExpStr` and `HexStr` are declared in both units today, in the frozen
copy as well as the live one, and have been for as long as `lib-test` has been
green — so the duplicate costs nothing that is not already being paid, and the
alternative (reverting the move) would have thrown away the no-uses-clause
reachability the move bought, on every one of the six, to fix two.

Measured before landing: the pinned compiler compiles a program calling all six
through `uses sysutils` and prints the fpc values; the same program against
`sysutils.pas` as it stood on origin/master answers `undefined variable
(SetString)` — the positive control fires.
