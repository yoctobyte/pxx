---
slug: chore-t-the-breadth-line-omits-its-zero-instead-of-printing-it
title: The breadth line reports an AGE with no work count, so idle and stalled read identically
track: T
type: chore
prio: 25
status: backlog
found: 2026-08-28
found-by: frank-coordinator (nearly escalated on it)
---

## The fact

`tools/twatch.py --status` prints two lines that answer the same kind of question very
differently:

```
tstate:   breadth — newest full tier is 3h old
tstate:   pin verify — v389 at 83468c5462d4 RED (full, 13h old), 4 red, 0 new vs the v389 baseline
tstate:            ...those reds are AT THE PINNED TREE, 33 testable commit(s) behind origin/master
```

The pin-verify line names **how far behind** it is. The breadth line names only **how old** it
is. And the breadth line *does* print a `N testable commit(s) behind` clause — but only when N
is nonzero, so **its absence is the zero.**

## Why that matters — measured, not hypothetical

Over three hours on 2026-08-28 the breadth figure went 1h → 2h → 3h while master took ten
commits, which reads as a watcher falling steadily behind. The coordinator set a threshold to
escalate at ~4h.

It was not falling behind. `git log <last-tested-sha>..origin/master --name-only` filtered to
non-docs paths returns **0 files**: every commit in the window was tickets, roster and
tstate's own output. Track T was fully caught up and had nothing to test.

> **An age is not a staleness measure when the input rate is zero.** A metric that reports
> elapsed time rather than unprocessed work returns the same number whether the system is
> STALLED or IDLE — and those need opposite responses.

## The fix

Print the count unconditionally, including when it is zero:

```
breadth — newest full tier is 3h old, 0 testable commit(s) behind   ← nothing to do
breadth — newest full tier is 3h old, 9 testable commit(s) behind   ← actually behind
```

One line, and it removes the entire class of misreading. The reader currently has to know that
a clause exists in order to interpret its absence, which is not something an occasional reader
of this output can be expected to know.

## Related

Same generator as the rest of the family in
`feature-a-a-refusal-is-a-claim-with-a-date-on-it`: **a state that carries no information
because two different conditions produce the same reading.** Here the omission is the payload,
and an omission is indistinguishable from "this was never measured."

Note the ticket is p25 deliberately — nothing is broken and no verdict is wrong. The cost is a
reader escalating on a healthy watcher, which is the cheap end of the same disease.
