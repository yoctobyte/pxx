---
slug: bug-n-a-bytes-payload-is-not-nul-terminated-so-a-c-string-seam-reads-past-it
title: a bytes payload is not NUL-terminated so a C string seam reads past it
summary: >
  FIXED. TPyBytes allocated exactly FLen bytes, so `FData` was only
  accidentally a valid C string -- correct whenever the allocator happened to
  leave a zero after the payload, wrong when it did not. `"u_zenith".encode(
  "ascii")` therefore reached glGetUniformLocation as a NINE-character name and
  the lookup answered -1. This is why lekkerzeilen drew a sky and no geometry:
  the four uniform names of length 8 (u_zenith, u_aspect, u_ground, u_colour)
  silently never bound, while every name of another length did. Fixed by
  allocating FLen + 1 and writing the terminator, in both the constructor and
  the grow path -- the guarantee CPython makes about a bytes object, and for
  the same reason.
track: N
type: bug
prio: 85
owner: frank-user
status: done
---

## How it was found

lekkerzeilen's capture was 78% one flat colour. The non-background pixels were
rows 0-197 of 900, full width -- a sky gradient and nothing else. The flat
colour below it was `(168, 186, 199)`, which is `SKY = (0.66, 0.73, 0.78)`
times 255 exactly, so the sky shader's own `u_horizon` WAS reaching the
program: uniforms worked.

Instrumenting `gfx.Shader._location` printed the discriminator:

```
PROBELOC sky  u_horizon    -> 2   handle 9
PROBELOC sky  u_zenith     -> -1  handle 9
PROBELOC sky  u_aspect     -> -1  handle 9
PROBELOC hull u_projection -> 8   handle 3
PROBELOC hull u_ground     -> -1  handle 3
PROBELOC hull u_colour     -> -1  handle 3
```

Nine of eleven hull uniforms bound, and the locations that came back were
`0,1,3,5,6,7,8,9,10` -- 2 and 4 missing, exactly the two names that answered
-1. **Every failing name is eight characters long.** Every succeeding one is
4, 5, 6, 7, 9, 10 or 12.

```python
import "/usr/include/string.h"
print(strlen("u_zenith".encode("ascii")))   # 9, for an eight-byte payload
```

## Root cause

`TPyBytes.Create(n)` did `GetMem(FData, n)` and `PyBytesEnsure` did
`GetMem(np, need)`. No terminator, ever. A `bytes` handed to a C `const char *`
was therefore correct only when the next byte in the heap happened to be zero.

## The fix

`compiler/builtin/pylib.pas`: allocate `n + 1` / `need + 1` and store a zero at
`[n]` / `[need]`, in both sites. `FLen` is untouched, so nothing Python can
observe moves. The empty case now allocates too, rather than leaving `FData`
nil -- `b""` handed to a `const char *` must be the empty C string, and on the
pinned compiler that row SEGFAULTS.

## The owner's objection, and what measuring it said

Raised the same evening, unprompted: *"those trailing zero's, i do recall
specifying that once as property of ansistrings (let's always allocate 1 byte
more than string length to easify pchar conversion), i'm not even sure we do
that. but for a bytearray that sounds wrong."*

Both halves checked rather than argued.

**We do that, and it is his.** `compiler/builtin/builtinheap.pas` allocates
`len + PXX_HDR_SIZE + 1` at every managed-string site and says `{ +1 = nul
terminator }` in its own margin (2222, 2386, 2485, 3172, and the in-place
resize at 5006); 2458 states the consequence outright -- *"PChar/PAnsiChar of a
managed string: the handle is already the NUL-terminated data pointer"*.
WideString carries a 2-byte NUL for the same reason. So the invariant has been
there all along and TPyBytes was the ONE thing outside it -- a pylib class with
its own `GetMem`, which is exactly why it was missed. This change does not add
a property; it stops an outlier.

**"For a bytearray that sounds wrong" is the right instinct and it costs
nothing here, because the byte is not part of the value.** `FLen` is untouched,
so `len`, iteration, slicing, concatenation, comparison and `repr` all read
what they read before -- measured against CPython, every row identical,
including `b"ab\x00cd"` (embedded NUL) and `b""`. CPython makes the same
guarantee for BOTH types: `PyBytes_AsString` and `PyByteArray_AsString` each
promise a trailing NUL. The cost is one byte per object.

**The limit worth knowing, and it is the honest half:** the terminator fixes
*reads past the end*, NOT *means the right thing*. A bytes with an embedded
NUL handed to a C string API still truncates, and no allocation policy can fix
that. Every C API that takes a LENGTH -- `glBufferData`, `write` -- already
receives `FData` plus `FLen` and never needed this. The terminator is
load-bearing only for genuinely NUL-terminated C APIs, and the demo's hot path
has one with no length parameter at all: `glGetUniformLocation(program, const
GLchar *name)`.

**The fork, if the one byte is ever judged not worth it:** terminate lazily
inside `pybytes_cbuf`, the single function that hands a bytes to a C pointer.
Not taken, and not merely for simplicity -- a WRITER (`glGenTextures(1, ids)`,
`SDL_PollEvent(ev)`) writes into that buffer, so it must be the object's own
storage and not a copy; and reallocating from what is nominally a read path
would make the extra byte sometimes-present, which is harder to reason about
than always-present. Recorded here so the option is visible rather than
rediscovered.

## Why no probe had caught it

WHICH lengths go wrong is not a property of the language; it is whatever the
allocator put after the payload. In one program only length 8 was wrong and
1..7 and 9..24 were all correct by accident. In the fixture's own program on
the pinned compiler, 8 AND 16 are wrong. So a probe that samples a few lengths
passes, and the natural lengths to reach for are short ones. The fixture sweeps
1..16 exhaustively for that reason, and says so in its own comment.

## What it does NOT fix

A bytes EXPRESSION written straight into a C-seam argument -- `strlen(
s.encode("ascii"))`, `strlen(b"abcdefgh")` -- still passes the wrong pointer
and answers a constant 3 at every length. Separate defect, separate ticket:
bug-n-a-bytes-expression-in-a-c-seam-argument-passes-the-wrong-pointer. The
fixture here deliberately routes every row through a variable so it cannot
redden for that one.

## Gate

`make test-nilpy`; self-host `converged`; new fixture
`test/test_nilpy_a_bytes_payload_is_nul_terminated_for_a_c_string_seam.npy`,
wired into the Makefile, GREEN at HEAD and RED against the pinned compiler
(`encode 1..16 : 8->9 16->17`, then a segfault on the empty row).

## Log
- 2026-09-14 -- found, fixed, fixture wired, landed.
