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

## A SECOND defect in the same object, found 2026-09-22 and NOT measurable while the segfault stands

`TPyDeque.Compact` rebuilds the buffer and installs it with `FBuf := nb` — and
**never releases the old `FBuf`**. Nothing else releases it either: `FBuf` does
not appear in any release, destructor or finalizer arm in `pylib.pas`. So every
`Compact` strands an entire buffer, and `Compact` is on the ordinary paths —
`appendleft` when the front is full, and `popleft` once the dead prefix reaches
half the buffer. A deque used as a queue would leak proportionally to traffic.

**Found by censusing the unreleased-temporary shape for
`bug-n-a-pylib-temporary-tpylist-is-never-freed`, not by running anything, and
it is recorded here rather than fixed because I cannot verify it: `deque()`
segfaults before it can leak.** Every other site in that census was confirmed by
measuring bytes/call against CPython and re-measuring after the fix. This one
has no such evidence and I am not patching an allocator path on a reading alone.

**For whoever clears the segfault:** measure `Compact` before assuming this, and
note the release must come BEFORE the field is overwritten, or the handle is
gone. The sibling fixes landed the same day in `pylist_setslice` and the
`pyiter_drain` family show the shape.

