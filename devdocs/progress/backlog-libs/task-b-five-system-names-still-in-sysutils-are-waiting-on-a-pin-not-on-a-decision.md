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
summary: "LowerCase, StrLen, StrPas, SysBackTraceStr and StringOfChar belong in compiler/builtin/builtin.pas beside the six moved at task-b-nineteen-sysutils-names-that-fpc-keeps-in-system, and are the only members of that population still unreachable from a no-uses program or unit. Nothing is undecided about them: they stayed because lib/rtl builds with $(PXX_STABLE) against a FROZEN copy of compiler/builtin, so moving a name that build calls deletes it from the only place it can look -- measured 2026-09-09, `make lib-test` failed EVERY unit with `undefined variable (LowerCase)` raised from inside sysutils.pas, and a second round with `undefined variable (StringOfChar)` at lib_strpchar.pas:49. THE TRIGGER IS A PIN carrying the unit-level pre-scan added in that ticket (pasparser_proc.inc) plus a refreshed frozen builtin; the whole test is compiling a UNIT that calls LowerCase with no `uses` under stable_linux_amd64/default/pinned, which fails today. Do NOT start this before that pin exists -- it will fail lib-test for a reason unrelated to the change. `Error` is a sixth name and is NOT part of this row: it is compiler-internal here and needs sysutils' exception hierarchy first."
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
3. Add each name to BOTH pre-scans: the call-shaped group in
   `pasparser_prog.inc` and the `unitNeedsBuiltinSys` clause in
   `pasparser_proc.inc`. A builtin that is declared and never dragged in answers
   `undefined variable`, which is the symptom being fixed.
4. Extend the two fixtures rather than writing new ones —
   `test/test_b_system_names_reach_a_program_with_no_uses_clause.pas` (program
   half) and `test/units/uambientsys.pas` +
   `test/test_unit_ambient_system_surface.pas` (unit half). The unit fixture's
   PROGRAM must go on naming none of the routines; that absence is what makes
   the unit-level pull the thing under test.
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
