# The 28 riscv32 skip reasons: one commit, one sentence, six families

**The reading half of the twenty-three, done without running anything.** No
compile, no qemu, no CPU taken from the full tier the fleet is holding pushes
for. Everything here is `git blame` and one commit message.

## Measured

All 28 live rows carrying *"backend feature gap (see bug-test-riscv32-thin-
coverage notes)"* were written by **one commit**, and none has been touched
since:

    28 lines   2aa06f4981   2026-07-14
     1 line    57ba5677a2   2026-08-27   (the UN-SKIPPED note, not a skip)

So the question *"is this reason still true"* was the wrong first question for
every one of them. **The right one is "was this row ever checked individually",
and the blame says no** — they were not written a row at a time.

## What the commit actually knew, and where it went

`2aa06f4981` was not careless. Its message carries a **taxonomy**:

> 35 stanzas the riscv32 backend genuinely cannot run yet are explicit `# SKIP`
> lines (variant/var_store, rtti_reg/class-RTTI, interfaces, dynamic externs,
> SYS_gettid timers, `in`-operator builtin), each pointing at the ticket

**Six named families, and a real basis for each.** What reached the Makefile was
one identical sentence on all 28 rows. The per-row reason was never recorded —
**the information was lost at WRITE time, not by decay.**

That is the mechanism behind "a placeholder that acquired the grammar of one".
It did not start as a placeholder. It started as a lossy projection of a real
taxonomy, and the taxonomy has lived only in a 54-day-old commit message ever
since. Every later reader inherits a sentence that **cannot be checked against
the row it sits on**, because it does not say anything specific to that row.

Note also the drift in count: the commit says 35, today 28 carry the string, and
two were un-skipped at `57ba5677a2`. The remainder are unaccounted for here.

## The 28 mapped back onto the six families

This is the deliverable: it turns 23 unchecked rows into roughly six checkable
questions, each answerable once for a group.

| family | rows |
| --- | --- |
| class-RTTI / streaming | `test_classref` `test_class_of` `test_rtti` `test_streaming` `test_streaming_enumset` `test_lfm` |
| interfaces | `test_interface_arc` `test_interfaces_is` `test_interfaces_as` `test_interfaces_param` `test_interfaces_inherit` |
| SYS_gettid timers / reactor | `test_timer` `test_reactor` `test_asyncecho` |
| scheduler / channels | `test_scheduler` `test_scheduler_exc` `test_channel` |
| dynamic externs | `test_extern_c` `test_extern_c_float` |
| `in`-operator / for-in | `test_forin_implicit_field` `test_forin_member_access` |
| **unmapped — name does not place them** | `test_arm32_virtual_wide` `test_cross_syscall` `test_cross_frozen_strlen_deref` `test_cross_managed_aggregate_locals` `test_cross_var_string_param` `test_cross_aggregate_return` `cunsigned_div_mod_b123.c` |

**The mapping is by NAME and is a hypothesis, not a measurement.** It is offered
to make the run phase cheap, and any row whose family answer disagrees with its
own result should be believed over this table.

**The seven unmapped rows are the most interesting**, not the least: their names
do not obviously belong to any family the commit listed, which means either the
taxonomy was incomplete or those rows were skipped for a reason nobody wrote
down anywhere. `test_timer` is already known to be a live HANG (rc=124), and it
sits in a family that WAS named — so the mapped rows are not safe either.

## Why this is not a ticket

Consistent with the standing ruling that the tier-publication gap is not a
Track T defect: **nothing here misbehaved.** A commit recorded a real taxonomy in
the place commit messages go, and the Makefile comment format had no slot for
it. The defect, if there is one, is that a skip reason is free-text with no
field for WHICH gap — and that belongs to whoever owns the skip format, not
here.
