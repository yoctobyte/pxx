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
summary: "LowerCase, StrLen, StrPas, SysBackTraceStr and StringOfChar belong in compiler/builtin/builtin.pas beside the six moved at task-b-nineteen-sysutils-names-that-fpc-keeps-in-system, and are the only members of that population still unreachable from a no-uses program or unit. Nothing is undecided about them: they stayed because lib/rtl builds with $(PXX_STABLE) against a FROZEN copy of compiler/builtin, so moving a name that build calls deletes it from the only place it can look -- measured 2026-09-09, `make lib-test` failed EVERY unit with `undefined variable (LowerCase)` raised from inside sysutils.pas, and a second round with `undefined variable (StringOfChar)` at lib_strpchar.pas:49. THE TRIGGER IS A PIN carrying a refreshed frozen builtin; the whole test is compiling a UNIT that calls LowerCase with no `uses` under stable_linux_amd64/default/pinned, which fails today. Do NOT start this before that pin exists -- it will fail lib-test for a reason unrelated to the change. `Error` is a sixth name and is NOT part of this row: it is compiler-internal here and needs sysutils' exception hierarchy first."
---

# Five names are one pin away, and the blocker is mechanical

## What to do, once the trigger has fired

1. Confirm the trigger: compile a UNIT that calls `LowerCase` with no `uses`
   under `stable_linux_amd64/default/pinned`. **It must fail today** — that is
   the positive control, and it stops passing exactly when the pin carries the
   unit-level pre-scan and a refreshed frozen `builtin/`. A green there before
   the work starts means the control is drawn from the wrong tree.
2. Move the five declarations and bodies from `lib/rtl/sysutils.pas` into
   `compiler/builtin/builtin.pas`, MOVED not copied — two homes for one routine
   is the defect class, not a mitigation of it.
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

## The population to check before moving anything

`grep` for each name across **everything the pinned build compiles**, which is
`lib/`, `examples/` AND the `test/lib_` rows. Missing that last group is what
cost the second round: the first consumer grep covered the first two and
StringOfChar failed anyway.

## Provenance

Split out of `task-b-nineteen-sysutils-names-that-fpc-keeps-in-system` so its
summary could be true — six of twelve landed, and the rest is not a smaller
version of the same question.
