---
track: A
prio: 85
type: bug
---

# The pxx allocator corrupts after a NilPy dict literal + repeated class allocation

Silent, and reachable from ordinary code. Repro, whole file:

```python
import json
d = {"a": 1}                  # a NilPy dict LITERAL — never used again
s = '{"a": 1}'
print(json.loads(s)["a"])     # 1
print(json.loads(s)["a"])     # CRASH ("Unhandled exception")
```

Remove the dict literal and both parses succeed. Keep it and the SECOND parse
dies — the first is fine, so it is state left behind rather than a bad parse.

**It is the allocator.** The same program compiled with `-dPXX_LIBC_HEAP`
prints `1 1` and exits clean. That is the same discriminator as
[[bug-c-unit-crashes-when-sysutils-is-used]], which also passes under the libc
heap, so the two are probably one bug.

`json.loads` here allocates a TJSONValue tree (Pascal classes) and converts it
into TPyDict/TPyList (pylib classes). The dict literal allocates a TPyDict up
front. So the shape is: allocate a pylib container, then allocate and free a
mixed set of class instances twice. Nothing in the Python source is unusual —
this is what any program that reads a settings file does.

## Why it matters now

It is what stops songformatter's session file from round-tripping:
`json.dump(...)` then `json.load(...)` in one run raises KeyError on a key that
IS in the file (the file on disk is correct — `cat` it). The `json` surface
itself is right: every operation is correct in a program that does one of them.

## Gate

`make test-nilpy` plus the repro above as a `.npy`, diffed against CPython —
and the same program under `-dPXX_LIBC_HEAP`, which must agree. Worth running
under valgrind with the pxx heap to name the offending block.
