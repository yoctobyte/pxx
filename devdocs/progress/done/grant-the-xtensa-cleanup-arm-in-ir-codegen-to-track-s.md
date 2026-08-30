---
slug: grant-the-xtensa-cleanup-arm-in-ir-codegen-to-track-s
track: A
prio: 55
status: done
---

# GRANT: the xtensa arm of `EmitManagedLocalCleanupForTarget` → Track S

**Granted 2026-08-30, with the incumbent lane's measured consent.** Scope is the
`if TargetArch = TARGET_XTENSA then` block inside
`EmitManagedLocalCleanupForTarget` (`compiler/ir_codegen.inc:10680`) **and nothing
else in that file.**

## Why it needed a grant and why it is safe

`ir_codegen.inc` was live: frank-optimize-b4's W1 `-O3` slice campaign, four
numbered slices in three hours. Rather than judge the distance myself, I asked —
and it **measured** its own footprint instead of estimating: slices touched lines
~2280-2351, 6247, 6875, 9591, 9654, the nearest **over 1000 lines** from 10680 and
in a different procedure; its remaining planned work (B and C) lives at ~6000-6300
and in `EmitLoadVar`'s resident arm. Disjoint. Consent given as option 1, take it now.

It also declined to take the work itself while already holding the file, on the
right grounds: **re-deriving xtensa machine code when riscv32's arm is complete is
a second implementation**, which is what `normalise-dont-special-case.md` and this
whole ticket family keep finding. The port is verbatim, not a re-derivation.

## The work

Port riscv32's six rows into the xtensa block immediately above it. Managed kinds
each arm releases, counted by parsing the procedure at two revisions:

| arm | at `0f48fa6a9` (2026-08-21) | at HEAD |
| --- | --- | --- |
| i386 | 4 | **7** |
| arm32 | 6 | **7** |
| aarch64 | 7 | **7** |
| riscv32 | 3 | **7** |
| **xtensa** | **1** | **1** |

Xtensa releases a scalar `AnsiString` and nothing else. Missing: COM interface,
static array of managed, Variant, promo-int, record with managed fields, dynamic
array. Two divergences are downstream — `test_managed_local_release_reuse` scores
1/5 against the oracle, `test_interface_arc` prints `freed=1` where the oracle
says `freed=3` (the COM-interface row).

riscv32 is the right donor: closest ABI, 32-bit, same helper set, arm now complete.

**Gate:** Track A's — `gate.sh quick` as well as the fixedpoint, since the file is
shared and another lane is working elsewhere in it. Coordinate the push order with
frank-optimize-b4 rather than assuming a clean rebase.

## Provenance

frankS, `bug-a-xtensa-scope-exit-releases-one-of-seven-managed-kinds` [A p55].
The finding behind it is banked as face 118: `0f48fa6a9` gathered these six arms
into one procedure **specifically to stop them drifting**, and two arms then grew
inside it, twenty lines from xtensa's one row, four separate times. Co-location
makes drift visible; only an oracle makes it fail.

## Log

- 2026-08-30 — **closed WITHOUT doing the work: it had already landed.** Not a
  duplicate-effort near-miss caught late, but the first thing a read of the file
  showed. The xtensa arm of `EmitManagedLocalCleanupForTarget` releases **7 of
  7** managed kinds at HEAD, not 1.
- 2026-08-30 — resolved, commit a0c727cbe.

### Evidence, since "it looks done" is not the same as "it works"

| check | result |
| --- | --- |
| six kinds landed | `e1d7977a2` *"xtensa's scope-exit release goes from one managed kind to six"*, an ancestor of HEAD |
| the seventh (dyn array) | `3a1c1dc73`, with the retain-before-release ordering argument in its comment |
| provenance ticket | `bug-a-xtensa-scope-exit-releases-one-of-seven-managed-kinds` is already in `done/` |
| `test_managed_local_release_reuse` | **MATCH** vs the x86-64 oracle (this ticket recorded 1/5) |
| `test_interface_arc` | **MATCH** (this ticket recorded `freed=1` where the oracle says `freed=3`) |

Both divergences this ticket named as downstream symptoms are gone, measured at
HEAD rather than inferred from the diff.

### The grant itself was sound; the ticket's picture of the tree was stale

Worth separating, because the failure here is not in the grant machinery. The
scope was precise, the incumbent lane's consent was measured rather than
estimated, and the coordinator verified three ways that `ir_codegen.inc` was
free before handing it over. All of that was correct work. What nobody re-ran
was the **counting query the ticket was built on** — `xtensa: 1` was true when
written and false by the time it was dispatched, and a grant ticket carries its
evidence in prose where nothing re-evaluates it.

A ticket whose body is a measurement has an expiry date that nothing in the
board prints.
- 2026-08-30 — resolved, commit a0c727cbe.
