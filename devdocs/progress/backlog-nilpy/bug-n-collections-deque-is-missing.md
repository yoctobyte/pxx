---
slug: bug-n-collections-deque-is-missing
track: N
prio: 40
type: bug
status: backlog
owner: ""
created: 2026-09-08
found-by: frankuser
tags: [nilpy, stdlib, collections, lekkerzeilen]
blocked-by: []
summary: "`collections.deque` does not resolve -- `no member deque came of the qualifier collections`. Measured 2026-09-08 against compiler/pascal26 a7b03135f504; blocks lekkerzeilen/chart.py:119. `collections` itself resolves (the parser knows the name), so this is a missing member on a qualifier that exists, not a missing module."
---

# Repro

```
$ ./compiler/pascal26 lekkerzeilen/chart.py out
pascal26:119: error: no member deque came of the qualifier collections
```

# Note on scope

The usage to satisfy first is the ring-buffer one: bounded `deque(maxlen=N)`,
`append`, `popleft`, iteration and `len`. That is what a scrolling chart wants
and it is the common case in real code generally; the full deque API
(`rotate`, `extendleft`, negative-index insert) can follow if anything asks.
