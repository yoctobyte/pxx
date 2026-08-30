---
slug: bug-a-a-shortstring-write-on-xtensa-corrupts-a-neighbouring-variable
track: A+S
prio: 70
type: bug
status: open
found: 2026-08-30
---

# A shortstring write on xtensa corrupts a NEIGHBOURING variable

`test_shortstring_trunc` prints `b-CLOBBERED` on hosted xtensa. A shortstring write is
running past its target and into the variable next to it. **This is memory corruption, not
a wrong string.**

Measured by frankS at HEAD `fa01f7111`, compiler `a6b4e6e1816c` (verified fixedpoint, sha
differs from `pinned`), Call0 profile.

## Why this ticket exists as a ticket

frankS named it in the handback table rather than filing it, reasoning that *"a ticket I do
not work is worth less than a row someone reads"* — a fair rule, and I am overturning it
for **this** row and one other, not for the third.

The ranker reads frontmatter. A row in a table in a ticket body is invisible to
`ready`/`next`, has no prio, no track and **no owner**, and nothing re-checks it. Three
independent instances of exactly that failure landed tonight — a park stale for 12 days on
conditions met the day it was written, a regression cascade open with zero residual work,
and a Makefile comment promising a gate that never existed with three orphans accumulated
behind it. A wrong-**value** finding is the last thing that should be carried in prose.

The handback table stays as it is; it is the honest partition and it is more useful than
four thin tickets. These two get frontmatter because the ranker cannot see a table.

## Why the priority is 70 and not lower

**The only reason this is visible at all is that the test plants guard variables around the
target.** Nothing else in the corpus would have shown it — the write lands in a neighbour,
and a neighbour that is not printed is a neighbour that is silently wrong. So the observed
blast radius is a floor, not a measurement, and the corpus's silence elsewhere is evidence
about the corpus rather than about the bug.

CLAUDE.md's escape rule applies directly: a finding that means *silent wrong behaviour* is
a `bug-` in the owning lane, never a compat or formatting item.

## Where to start

Not the shortstring truncation logic — the **bound** it truncates to, and whether the store
width is computed from the declared capacity or from the source length. Grep the sibling
before closing: the by-value wide-record divergence
(`bug-a-a-by-value-wide-record-on-xtensa-renders-a-live-address`) is the same night's
second wrong-value finding and may share a store path.
