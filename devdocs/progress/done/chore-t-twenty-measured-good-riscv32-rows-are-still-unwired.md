---
slug: chore-t-twenty-measured-good-riscv32-rows-are-still-unwired
title: "20 riscv32 rows match the x86-64 oracle today and nothing enforces it — measured, not wired"
track: T
prio: 55
type: chore
status: done
owner: unassigned
created: 2026-09-06
found-by: frank-subcoord (the rv32 skip census)
summary: "Of 25 Makefile rows skipped on riscv32 as 'backend feature gap', I measured every one against the x86-64 oracle: 21 match exactly. THREE are now wired (test_timer, which was hiding a real hang, plus test_reactor and test_asyncecho); test_cross_syscall was missing an rv32 arm and is fixed and matching. That leaves 20 rows that PASS TODAY and that nothing checks — measured-good is not coverage, and the next regression in any of them is invisible exactly as the hang was. Wiring is mechanical (compile for rv32, compile for x86-64, expect_same against the oracle, the pattern the neighbouring rows already use) but it is 20 rows of added test-core runtime, so it wants doing deliberately rather than in the middle of a release-candidate tier. test_rtti is NOT in the 20 and must not be wired this way — it prints raw addresses and InstanceSize, so it has no cross-target oracle by construction and needs frankA's relation form instead."
---

# Measured-good is not coverage

The census behind this is in `bug-a-rv32-has-no-timerfd-settime-and-three-skips-hid-it`
and the 2026-09-06 LOGBOOK entry. Short version: 25 rows carried one identical
sentence, *"backend feature gap (see bug-test-riscv32-thin-coverage notes)"*,
and exactly **two** of them are what it claims.

| outcome | count | state |
| --- | --- | --- |
| match the x86-64 oracle | 21 | **3 wired**, 1 fixed+matching, **20 still unwired** |
| genuinely refuse (both `extern_c`) | 2 | correct skips, keep, reason is accurate |
| no cross-target oracle possible (`test_rtti`) | 1 | skip legitimate, REASON wrong — frankA's relation form |
| was a hang (`test_timer`) | 1 | fixed and wired |

(The counts overlap: `test_timer` and `test_cross_syscall` are inside the 21
because they match the oracle *after* being fixed.)

## The rows

Everything under `# SKIP ... on riscv32` in the Makefile except
`test_extern_c.pas`, `test_extern_c_float.pas`, `test_rtti.pas`, and the three
already wired. They cover interfaces (`as`/`is`/`inherit`/`param`/`arc`),
class refs (`class_of`, `classref`), streaming (`streaming`,
`streaming_enumset`, `lfm`), `for-in` (`implicit_field`, `member_access`), the
cross-* aggregate/string/managed-locals set, `channel`, `scheduler`,
`scheduler_exc`, `arm32_virtual_wide`, and `cunsigned_div_mod_b123`.

## Why this is not just "go wire them"

1. **Runtime.** 20 rows × (rv32 build + x86-64 build + two qemu runs) is real
   time added to `test-core`, which every lane pays. Worth doing; worth doing
   when a candidate tier is not in flight.
2. **A passing row today is not a stable row.** These have never been enforced,
   so none has ever been shown to be non-flaky. Wire them and watch one tier
   before treating them as coverage.
3. **Do not batch `test_rtti` in.** It fails the oracle for a correct reason and
   would either be "fixed" by baking x86-64's constants into it or left looking
   like a real rv32 defect. It needs relations, not an oracle.

## The reason string itself

Whoever does this should also **delete the sentence from the rows that keep a
skip** and give each its own real reason. One boilerplate line across 25 rows is
what let a hang hide for as long as it did: a reason that is true of the group
when written goes stale per-row, and nothing re-reads it because it sounds
settled. The two `extern_c` rows already show the right form — they name the
refusal, and the refusal is checkable in one command.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
