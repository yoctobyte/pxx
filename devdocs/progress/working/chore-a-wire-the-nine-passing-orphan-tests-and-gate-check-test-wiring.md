---
slug: chore-a-wire-the-nine-passing-orphan-tests-and-gate-check-test-wiring
title: "Wire the nine orphan tests that already pass at HEAD, then gate tools/check_test_wiring.py"
track: A
type: chore
prio: 40
status: working
found: 2026-08-29
found-by: pxx-a5 (Track T)
owner: pxx-a5
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

---

## Wired — 2026-08-29, ELEVEN not nine

`Makefile`, one block after the ecdsa rows of the earlier sweep's batch 2.
Compiler at `4843c777a`, self-hosted binary `28a17f797b64`, fixedpoint verified.

**The list was a snapshot, not a census, and it aged in one day.** The nine
above were taken at `f576ec79d`; by the time the wiring ran, `check_test_wiring`
reported **23** unwired, not 21. The two extras —
`test_o3_float_resident.pas` (`3e9c12e24`) and `test_o3_resident_exc.pas`
(`9d46bff96`) — are Track O residency probes that landed the same day, and
neither is an ancestor of the triage sha. Both were wired here too, because the
gate below cannot land while the backlog is non-empty and leaving two behind
would have reproduced the exact condition this ticket exists to end. That the
population grew by two while nine were being drained is the argument for the
gate, stated by the backlog itself.

### What each one asserts, and where the expectation came from

The rule the whole block obeys: **none of the eleven had ever run, so "it passes
at HEAD" was never evidence.** A `.expected` transcribed from today's output
would defend whatever today's output happens to be — and for two of them
(`042bcbb32`, `7ee75329e`) the file *shipped as the regression test for its own
fix*, so today's output is precisely the thing under suspicion.

| file | expectation | oracle |
| --- | --- | --- |
| `test_class_arg_to_pointer_param_boundary` | 8 values | **FPC 3.2.2 `-Mobjfpc`**, byte for byte |
| `test_class_method_to_method_pointer` | 7 values | **FPC**, byte for byte |
| `test_generic_delphi_method_header_binds_to_the_generic` | 7 values | **FPC**, byte for byte |
| `test_generic_nested_type_field_name` | 2 lines | **FPC**, byte for byte |
| `test_generic_nested_type_identity` | 3 lines | **FPC**, byte for byte |
| `test_o3_resident_inplace` | cross-O + 11 lines | **FPC** on 10 of 11 rows (see below) |
| `test_o3_float_resident` | cross-O + 9 lines | **FPC**, byte for byte |
| `test_o3_resident_exc` | cross-O + 7 lines | **FPC**, byte for byte |
| `test_softfloat_double` | the 6-line counter block | **hardware IEEE binary64**, by the file itself |
| `test_softfloat_single` | the 7-line counter block | **hardware IEEE binary32**, by the file itself |
| `test_pyexec_trampoline_abi` | 5 lines | **none — the author's**, transcribed from the file's own trailing comments |

Eight independent oracles, two self-checking against hardware, one honestly
labelled as having neither. The last row is the `test_promoint_bitwise`
precedent: pxx's RTTI (`GetInstanceRTTI` / `GetMethInfoByName`) has no FPC
equivalent, so the file cannot be compiled there at all, and the values are the
ones the author wrote in `{ 32 }` / `{ 10 }` / `{ 4.00 }` / `{ 2.50 }` comments
beside each `writeln` — not our output recorded and relabelled.

The softfloat rows assert the **whole counter block**, not `RESULT: PASS`. The
single-precision file tolerates 1-ulp division error and subnormal flushes, so
`PASS` can coexist with a nonzero tolerated count; asserting only the verdict
would let a drift into the tolerance go unseen.

### One row where FPC and pxx disagree, and it is not a defect

`test_o3_resident_inplace` prints `Q ovf=TRUE` under pxx and `Q ovf=FALSE` under
FPC. Reduced to a standalone probe under both compilers before the value was
written down, because "ours differs from FPC" is exactly the shape that gets
recorded as a bug on a plausible story:

- The procedure is wrapped in `{$Q+}` and adds `100000000` to a `LongInt` forty
  times. pxx evaluates `LongInt + LongInt` in 32 bits, the add overflows, and
  `{$Q+}` raises.
- FPC widens both operands to `Int64` first, so **no overflow occurs at all** —
  neither `{$Q+}` nor `-Co` fires. Only `-Cr` does, and it fires on the
  narrowing store back to `LongInt`, raising `ERangeError` rather than
  `EIntOverflow`.
- Both compilers **store the same value**, `-294967296`. Only the check differs.

So it is an integer-promotion-width divergence, observable solely through a
check directive, and the two agree on every value. Worth knowing that the first
reading was wrong: the `-Co` probe answered `FALSE` and looked like FPC ignoring
its own directive, which is a much more alarming claim than the true one.

### Verified, and how

- The block was extracted, macro-expanded and run **in a clean empty tmp dir**
  so no stale binary from an earlier run could satisfy a mis-pointed rule. All
  28 commands green.
- Then every one of the 14 assertions was **deliberately corrupted** (a sentinel
  appended to the expectation) and re-run: **14 of 14 went red.** A rule that
  cannot fail is not a test, and nine rules added in one commit is exactly where
  a copy-paste target name survives unnoticed.
- `make -n compiler/pascal26` parses the Makefile; `make compiler/pascal26`
  converged in 2 rounds at `28a17f797b64`. No compiler source was touched.

### The gate is not landed yet, and the reason is a live one

`check_test_wiring` now reports **12** unwired, and all twelve are the
`test_pyeval_*` set belonging to
[[bug-n-the-only-callers-of-evalpystmts-encode-a-contract-that-changed]]. That
ticket is resolved — the twelve now pass — but *passing* and *wired* are
different things, and only the second one is what the gate counts. Gating today
would land a check that is red on arrival, which the parent ticket explicitly
refused to do because it teaches people to skip the step.

So the gate waits on those twelve being wired, and on nothing else.
