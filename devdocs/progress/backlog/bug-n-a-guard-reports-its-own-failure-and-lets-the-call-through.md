---
track: N
prio: 45
type: bug
blocked-by: []
summary: "sys.version_info throws at RUNTIME with a message admitting its own guard failed: 'the code guarding that (the flag its except-branch sets) let this call through anyway'. Two defects — the member is missing, and the compile-time guard meant to catch that does not fire. A guard that reports its own failure and continues is worse than no guard."
---

# A guard reports its own failure and lets the call through

- **Type:** bug — **Track N**. **Found:** 2026-08-18, jointly (frankonpiler-bf
  spotted the runtime throw; frank2-7e measured the boundary) while closing
  [[bug-n-from-sys-import-fails-while-import-sys-works]].
- **Measured at:** HEAD `7e7ed35d7` and pinned v349 — same on both.

## Repro

```python
import sys
print(sys.version_info)
```

```
Unhandled exception: Exception: this build has no sys.version_info: the import it
came from could not be resolved, and the code guarding that (the flag its
except-branch sets) let this call through anyway
```

## Two defects, and the second is the interesting one

1. **`sys.version_info` is not provided.** Other members are — `sys.argv` works,
   `os.getcwd()` works — so this is one absent member, not an unimplemented
   module. Providing it is a small decision with a question attached: what
   version does a NilPy build claim to be? Real code branches on it
   (`html5lib/_tokenizer.py:21` is `if version_info >= (3, 7)`), so answering
   too low silently selects legacy paths. **That part may want Track U.**

2. **The guard does not guard.** The message states plainly that a flag set in
   an except-branch was supposed to stop this call and did not. A guard that
   detects its own failure, says so, and proceeds anyway is worse than no guard:
   it converts a compile-time refusal into a runtime crash in the user's
   program, and it has clearly been failing long enough for someone to write the
   sentence describing it.

Defect 2 is independent of defect 1 — the guard would still be broken for the
next unprovided member. Fix it first; it is the one that generalises.
