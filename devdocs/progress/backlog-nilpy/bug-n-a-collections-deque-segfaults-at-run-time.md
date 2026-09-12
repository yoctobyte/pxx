---
slug: bug-n-a-collections-deque-segfaults-at-run-time
track: N
prio: 70
type: bug
blocked-by: []
status: backlog
found: 2026-09-12
found-by: frankuser
summary: "`collections.deque()` COMPILES and then SEGFAULTS at run time (rc=139), producing no output at all where CPython prints a value. Minimal: `q = collections.deque(); q.append(5); print(q.pop())` inside a function -- compiles clean, crashes. MEASURED ON BOTH SIDES of the 2026-09-12 candidate-promotion fix, with binaries built from the same tree minus that one hunk, so it is PRE-EXISTING and unrelated to it. The pin cannot serve as a control because it predates deque support entirely (`no member deque came of the qualifier collections`). A compiling program that crashes is worse than a refused one, and the crash is silent -- no diagnostic, no partial output."
---

# `collections.deque()` compiles and segfaults

## Measured

```python
import collections
def uses_a_deque():
    q = collections.deque()
    q.append(5)
    return q.pop()
print(uses_a_deque())
```

CPython prints `5`. pxx compiles clean (`ok:`) and the binary exits **139**
(SIGSEGV, core dumped) having printed nothing.

## Provenance — why this is not the promotion fix

Found while attempting a reduction for
`bug-n-a-dict-field-resolves-pop-against-a-list-or-deque-overload-set`, whose fix
touches the same method-candidate machinery, so attribution mattered. Built two
binaries from the same tree differing only in that hunk:

| fixture | pre-fix | post-fix |
| --- | --- | --- |
| deque only | rc=139 | rc=139 |
| deque + a dynamic `.pop(k, d)` | rc=139 | rc=139 |
| dynamic `.pop(k, d)` only | rc=0, matches CPython | rc=0, matches CPython |

Identical on both sides, so the crash is pre-existing. (That third row is also
why no fixture for the promotion fix exists — see that ticket.)

## What to do first

It is a CRASH, so it is the cheap case: it has a location. Run it under gdb with
`tools/pxx-gdb.py`, or build with `-dPXX_HEAP_DEBUG` (freed bytes become `$DD`)
and `-dPXX_OBJTRACE`. Do NOT start from the frontend — `q.pop()` is a zero-argument
call on a statically known container and the interesting question is what
`collections.deque()` actually constructs.

Note `TPyDeque` declares only `popleft` and `pop` (`compiler/builtin/pylib.pas:948-949`)
and has no `append`-family entry visible in the same block; check whether
`q.append(5)` bound to something else entirely before blaming `pop`.
