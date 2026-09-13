---
slug: bug-n-a-list-bound-to-a-c-pointer-to-pointer-parameter-passes-the-object-pointer
title: a list bound to a C pointer-to-pointer parameter passes the object pointer, not an array of element pointers
summary: >
  `glShaderSource(shader, 1, [encoded], None)` stores NOTHING in the driver. A
  Python LIST bound to a C pointer parameter passes the TPyList OBJECT pointer,
  so the callee reads the VMT word as its first `char *`. This is the direct
  sibling of the bytearray fix that landed today (`8d5fe5325`) one level up: that
  one was a pointer to DATA, this one needs a pointer to an ARRAY OF POINTERS,
  which does not exist yet and has to be built somewhere with a lifetime.
  THIS IS THE LIVE WALL ON lekkerzeilen: every shader in the program fails to
  link with the driver's own `error C5145: must write to gl_Position`, because
  the source it compiled was the empty string.
track: N
type: bug
prio: 80
owner: unassigned
status: done
---

## What was measured

2026-09-13, at HEAD with both of today's marshalling fixes in.

**From the driver's own side**, in `lekkerzeilen/platform/_pxx.py`'s
`gl.shader_source`, with two instruments that fail differently:

    SRC we hold len=390          <- our own bytes, correct
    DRV source_length=1          <- glGetShaderiv(GL_SHADER_SOURCE_LENGTH)
    DRV readback len=0           <- glGetShaderSource into a bytearray

and again for the 1339-byte fragment shader, same answer. An empty vertex
shader COMPILES, so nothing fails until the link, and the link says
`must write to gl_Position` — which reads like a shader bug and is an empty
string.

**What the list actually becomes**, asked of the callee rather than inferred
(the same method that settled the bytearray case):

    import "/usr/include/unistd.h"
    payload = b"ABCDEFGHIJKLMNOPQRSTUVWX"
    lst = [payload]
    write(1, payload, 24)      # A
    write(1, lst, 24)          # B

    A  ABCDEFGHIJKLMNOPQRSTUVWX
    B  p\xd2S\x00\x00\x00\x00\x00 \x01\x00\x00\x00\x08\x00\x00\x00 \xa8\x00`"\x85\x7f\x00\x00

Row B is a TPyList field for field: the VMT pointer, then the count 1, then the
capacity 8, then the heap pointer to the element array. So the callee is handed
the OBJECT, and `glShaderSource` dereferenced the VMT word as its first
`const char *`.

## Why it is not just the bytearray fix again

`pybytes_cbuf` / `pyvar_cbuf` answer "where is this object's DATA", and for a
bytes object that is one word it already holds. A `const GLchar *const *`
wants something that **does not exist in the heap yet**: an array of N pointers,
one per element, contiguous. Building it means allocating at the call site, and
that allocation has to outlive the call.

Three options, none free:

1. **A scratch array per call site.** Cheap and wrong the moment two such calls
   are live at once, or the callee retains the array (`glShaderSource` copies
   immediately; `execv` does not return; a callee that keeps it would break).
2. **Own it from the list.** Build the array into a buffer hung off the TPyList
   and keep it until the list is mutated or freed. Correct lifetime, costs a
   field on every list.
3. **Refuse it, and give the seam an explicit spelling** — a builtin that
   returns an owned pointer array the caller holds in a local. Least magic,
   most honest, and the call site stops looking like Python.

Recommendation: (2) for a list of `bytes`, which is the only element type any
measured call site uses, and a clear refusal with a named diagnostic for
anything else. An element that is not bytes has no stable data pointer at all,
so guessing is worse than refusing.

## The fork that is NOT ours

The umbrella licenses changing lekkerzeilen where a construct is *incidental*.
`[encoded]` is a candidate: it exists because the C signature wants an array,
and under CPython the seam built it with `ctypes.c_char_p`. But a list is also
the obvious Python spelling of "an array of strings", and **every** C API that
takes one (argv, `glShaderSource`, SDL's hint arrays) lands here, so fixing the
compiler is worth more than editing one call site. Both halves are open; do not
read the recommendation above as having settled it.

## Residual from the bytearray ticket, now partly measured

That ticket recorded `str` / `list` / `array` as never measured. `list` is
measured here and is broken. `str` and `array` remain unmeasured.

## Fixed 2026-09-13

**The array is built into a bytes object and owned by a hoisted named temp.**
`pylist_cptrarray(l: TPyList): TPyBytes` in `compiler/builtin/pylib.pas` fills
one pointer word per element -- `pybytes_cbuf` for a bytes element, the payload
word for anything else, so a trailing `None` becomes the NULL terminator C
wants. `PyCoerceCallableArgsIn` in `compiler/pyparser.inc` recognises a
statically TPyList-typed argument in an EXTERNAL callee's pointer parameter,
hoists `tmp := pylist_cptrarray(lst)` into the enclosing statement, and passes
`tmp`.

**Why a named temp and not a nested call**, which is the part worth keeping:
the array does not exist in the heap until it is built, so it needs an owner,
and the three candidates were a scratch pool (wrong the moment two are live), a
field on every TPyList (a layout change), and a caller-held object. Measured the
same day: a bytes reaching a C pointer parameter through a NAME is coerced
correctly and survives an intervening allocation, while the same bytes as a
nested pylib CALL RESULT passes the object pointer. So the nested spelling is
wrong for two independent reasons and the named one is right for both. The
argument then arrives as an AN_IDENT statically typed TPyBytes, which
`IRLowerCallArg`'s existing static arm already turns into `pybytes_cbuf(tmp)` --
no second answer to "where is this object's data".

**Still open, deliberately:** the VARIANT spelling. A list arriving through a
PARAMETER reaches `pyvar_cbuf`, which returns a Pointer and can own nothing, so
deciding at run time to build an array would put the array's owner inside a
function that has none. That half is unfixed and unguessed.

**The recommendation above is NOT taken**: `[encoded]` stays in lekkerzeilen's
seam, because a list is the obvious Python spelling of "an array of strings"
and every C API that takes one lands here.

**Verified:** `test/test_nilpy_a_list_reaches_a_c_pointer_to_pointer_parameter`
-- execv walks the array to its NULL and `/bin/echo` prints argv[1..], so the
readout is a callee that uses every pointer, which is the only honest assertion
available for an object the program cannot look at. Four pointers, so one
correct slot cannot carry the row; the `.expected` is derived rather than
captured. Under pin v408 the same program prints binary heap bytes.
lekkerzeilen now links every shader and reaches a new wall further in.

## Log

- 2026-09-13 | fixed in `compiler/builtin/pylib.pas` and
  `compiler/pyparser.inc`, commit PENDING-COMMIT.
- 2026-09-13 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit dca30fbae.
