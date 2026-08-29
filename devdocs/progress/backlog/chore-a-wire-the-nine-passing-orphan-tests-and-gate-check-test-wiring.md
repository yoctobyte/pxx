---
slug: chore-a-wire-the-nine-passing-orphan-tests-and-gate-check-test-wiring
title: "Wire the nine orphan tests that already pass at HEAD, then gate tools/check_test_wiring.py"
track: A
type: chore
prio: 40
blocked-by: [bug-n-the-only-callers-of-evalpystmts-encode-a-contract-that-changed]
status: backlog
found: 2026-08-29
found-by: pxx-a5 (Track T)
---

# Wire the nine that pass, then gate the checker

The last step of [[feature-t-fail-when-a-test-file-is-wired-into-no-build-rule]],
split out so the parent closes rather than sitting half-done. The checker is
built, measured and guarded; what remains is **Makefile wiring, which is Track
A's file-lane**, and the gate that becomes possible once the backlog is empty.

## The list, triaged by RUNNING them at HEAD

Twenty-one subjects are referenced by no rule. All were compiled and **run** at
HEAD `f576ec79d` (self-hosted binary `5c9d52bdd0bf`, fixedpoint verified), and
bucketed by the binary's own exit code:

| bucket | n | disposition |
| --- | --- | --- |
| **passes standalone (exit 0)** | **9** | wire it — this ticket |
| fails: stale exec contract | 12 | `bug-n-the-only-callers-of-evalpystmts-encode-a-contract-that-changed` |

The nine:

```
test_class_arg_to_pointer_param_boundary.pas
test_class_method_to_method_pointer.pas
test_generic_delphi_method_header_binds_to_the_generic.pas
test_generic_nested_type_field_name.pas
test_generic_nested_type_identity.pas
test_o3_resident_inplace.pas
test_pyexec_trampoline_abi.pas
test_softfloat_double.pas
test_softfloat_single.pas
```

**Two of them landed as the regression test for their own fix** — `042bcbb32`
(`fix(pfront)`: a Delphi generic method header must bind to the generic) and
`7ee75329e` (`fix(P)`: a nested type's identity is per-owner). Each shipped with
a test that has never run.

**None has an `.expected`.** So wiring one means deciding what it asserts. Three
already self-assert and only need a run rule: `test_softfloat_double` and
`test_softfloat_single` print `... fails : 0` counters, and
`test_o3_resident_inplace` is an `-O3` residency check. The rest print values
and want an expectation recorded.

## Then gate it

Once the list is empty, wire `tools/check_test_wiring.py` into `make test` (or
`tools/progress.sh check`) so a test file wired into nothing **fails** rather
than waiting for someone to notice. The parent ticket deliberately did not gate
it while it would be red on arrival — a check that is red the day it lands
teaches people to skip a step.

## Do not triage this list against the pinned binary

Recording the trap, because it cost a wrong answer on the way here and the
correction is cheap only if you know to make it. The same twenty-one were first
triaged with `stable_linux_amd64/default/pinned` (v389, **59 testable commits
behind**), which disagreed with HEAD on **three of twenty-one**:

| file | at the pin | at HEAD |
| --- | --- | --- |
| `test_class_method_to_method_pointer.pas` | **SIGSEGV (139)** | passes |
| `test_generic_delphi_method_header_binds_to_the_generic.pas` | compile error `undefined variable (FBump)` | passes |
| `test_generic_nested_type_identity.pas` | compile error `no such member "dd"` | passes |

All three are fixed at HEAD. Triaging against the pin would have filed three
phantom bugs — one of them a segfault, which is the kind that gets believed. Per
CLAUDE.md: *hunt async, verify against a known sha.*

The pin-side segfault is not wasted information, though, and it is the argument
for this ticket in one line: **a wired `test_class_method_to_method_pointer`
would have caught a real segfault at v389.** It did not, because nothing ran it.

## Gate

Track A's: `make compiler/pascal26` (the self-host fixedpoint) plus the newly
wired targets. Do not land concurrently with other A edits to `Makefile`.

## Two more, from the GTK side (frank-b, 2026-08-29)

`test/gui/test_gtk_window.pas` and `test/gui/test_gtk_signals.pas` are orphans
of the same kind: grepping `Makefile` and `tools/gui_suite.sh` for either name
returns nothing, so neither is run by anything. Confirmed here, not inherited —
frank-rust reported it during the PCL header migration and I re-ran the grep.

Adding them to this ticket rather than opening another, per its own premise.

They are worth a line beyond "two more of the nine", because they show the cost
side rather than the risk side: both were *converted* during the PCL migration
off the curated GTK3 header. Someone read them, edited them, and kept them
consistent with a binding change — maintenance paid in full on files that
cannot report anything. The existing framing here is "an unwired test does not
catch its bug"; these are the other half, "an unwired test still bills you for
upkeep", and the second half is the one that keeps being paid without anyone
deciding to.

Both reference `lib/pcl/gtk3_c.h`, so whoever wires them should pass `$(GTK3_INC)`
— that header now hard-asserts `GTK_MAJOR_VERSION >= 3` and will `#error`
without it, by design
([[feature-b-pcl-should-assert-its-gtk-version-rather-than-rely-on-an-accident]]).
