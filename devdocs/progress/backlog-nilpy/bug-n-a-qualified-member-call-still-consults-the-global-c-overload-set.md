---
slug: bug-n-a-qualified-member-call-still-consults-the-global-c-overload-set
track: N
prio: 55
type: bug
blocked-by: []
status: backlog
found: 2026-09-11
found-by: frankuser
owner: unassigned
summary: "`m.open(\"x\")` where a C header declares `int open(const char *, int)` fails with `no overload of open matches these arguments` -- the qualified member call is checked against the GLOBAL C overload set instead of the module's own member. Sibling of bug-n-a-field-assigned-a-class-or-none-in-two-methods-wont-widen, which fixed the INFERENCE walk's copy of this mistake; this is the CALL path and is still open. Found while trying to build a hermetic fixture for that bug: a hand-written two-parameter declaration of `open` fails at HEAD, and adding `...` to match glibc's variadic form does NOT fix it, so glibc's declaration differs from a hand-written one in some way that was NOT established."
---

# A qualified member call still consults the global C overload set

## Repro

`h.h`:

```c
int open(const char *path, int flags);
```

`m.py`:

```python
class World:
    def __init__(self, p):
        self.p = p
def open(name="x"):
    return World(name)
```

`t.py`:

```python
import "h.h"
import m
print(m.open("tiled").p)
```

```
error: no overload of open matches these arguments
```

`m.open` takes one argument and is a member of `m`. The arity being complained
about is the C function's.

## Why it is filed separately

`bug-n-a-field-assigned-a-class-or-none-in-two-methods-wont-widen` was the same
mistake in the RETURN-TYPE INFERENCE walk — `PyInferExprType` asked the global
`FindProc` for the member token of a qualified call, so a C `open` supplied the
type. That is fixed: the inference now asks `FindProcInUnit` against the
resolved unit first and falls back to the global, so a bare call is unaffected.

This is the same question asked by the CALL path, and the fix above does not
touch it. Two mechanisms serving one concept is the smell
`devdocs/dev/root-cause-over-microfix.md` names; whoever takes this should look
for a third before fixing the second.

## The part that is NOT explained, and it matters for whoever takes this

With glibc's real `fcntl.h` the same program COMPILES at HEAD. With a
hand-written declaration it does not, and making the local one variadic —
`int open(const char *path, int flags, ...);`, which is how glibc declares it —
does **not** make it compile either.

So something about what `fcntl.h` produces differs from a hand-written
declaration of apparently the same function, and that was not established. Two
candidates worth checking before anything else, neither verified: glibc's
declaration carries attributes/`__THROW` and may route through `__REDIRECT`, so
the recorded name or signature may not be what the source line reads; and the
header defines a large number of macros, one of which may shadow or rename the
symbol.

**This asymmetry is the useful lead, not an inconvenience** — it means the
overload set pxx builds from a real header is not the one a reader would predict
from the declaration, and whatever explains that probably explains this ticket.

## Collateral worth knowing

It is why `test_nilpy_a_qualified_member_loses_to_a_c_function_of_the_same_name`
imports `/usr/include/fcntl.h` and `/usr/include/unistd.h` rather than a small
local header, and therefore why it emits seventeen "resolved from the host
system" warnings per run. A local header would have been hermetic, quiet, and
independent of this box's glibc — and it pins a different bug. Fixing this
ticket would let that fixture become hermetic, which is a second reason to want
it done.
