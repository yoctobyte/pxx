---
slug: bug-n-a-bytes-expression-in-a-c-seam-argument-passes-the-wrong-pointer
title: a bytes expression in a C-seam argument passes the wrong pointer
summary: >
  FIXED. A bytes bound to an EXTERNAL C routine's pointer parameter arrived as
  its buffer only when the argument was a NAME or a FIELD -- that is all
  IRLowerCallArg's arm can recognise. Through a CALL RESULT or a LITERAL the
  TPyBytes INSTANCE went over, so `strlen(s.encode("ascii"))` answered a
  constant 3 at every length, and every mat4 uniform lekkerzeilen uploaded --
  `glUniformMatrix4fv(loc, 1, GL_FALSE, struct.pack("<16f", *values))` --
  arrived as an object header. The renderer drew its sky, which uses no
  matrices, and no geometry at all. Fixed in PyCoerceCallableArgsIn by hoisting
  such an argument into a named temp, which is the spelling the existing static
  arm already knows how to answer.
track: N
type: bug
prio: 85
owner: frank-user
status: done
---

## Repro

```python
import "/usr/include/string.h"


def via_param(b):
    return strlen(b)


s = "abcdefgh"
v = s.encode("ascii")
print(strlen(v))                    # 8  -- already correct
print(strlen(s.encode("ascii")))    # 3  -- WRONG
print(via_param(s.encode("ascii"))) # 8  -- correct: a parameter is a name
print(strlen(b"abcdefgh"))          # 3  -- WRONG
print(strlen("".encode("ascii")))   # 3  -- WRONG (want 0)
```

## The control this needs, and why the obvious probe certifies the bug

`strlen(b"abc")` answers 3, which is CORRECT, and three characters is the
natural length to reach for. The wrong answer is a CONSTANT that collides with
a plausible right one -- the same family as CLAUDE.md's "choose a probe whose
right answer differs from the default", by a door that list does not yet name:
not a width, not an empty aggregate, but a fixed wrong value that happens to be
right at one input. Every row in the fixture is eight characters for that
reason, and it says so in its own comment.

## The fix

`compiler/pyparser.inc`, `PyCoerceCallableArgsIn`: when an external callee's
`tyPointer` parameter receives a statically TPyBytes argument that is not
already an `AN_IDENT`, hoist it into a hidden named temp and pass the temp.
The argument is then exactly what `IRLowerCallArg`'s existing static arm turns
into `pybytes_cbuf(tmp)` -- one answer to "where is this object's data", not
two. It is the same hoist, for the same ownership reason, that the neighbouring
TPyList arm already performs: a temp in the enclosing routine outlives the
call, where a nested call result has no owner.

**One divergence it takes deliberately:** the hoisted argument is now evaluated
before the arguments to its left, where Python is strictly left to right. The
list arm above it already takes the same one, and there is no spelling here
that assigns a temp in place.

## Gate

`make test-nilpy`; self-host `converged`; new fixture
`test/test_nilpy_a_bytes_expression_reaches_a_c_pointer_parameter_as_its_buffer.npy`,
wired into the Makefile, GREEN at HEAD and RED against the pinned compiler
(`call result 3`, `literal 3`, `empty expr 3`).

## Log
- 2026-09-14 -- found while tracking lekkerzeilen's missing geometry, filed,
  and fixed the same evening, commit 925346238. Filed first as "an inline bytes literal ..."
  which was too narrow: the literal is one case of an expression and
  `"".encode()` is another.
