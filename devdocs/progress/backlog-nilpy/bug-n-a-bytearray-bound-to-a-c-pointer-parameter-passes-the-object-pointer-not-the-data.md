---
slug: bug-n-a-bytearray-bound-to-a-c-pointer-parameter-passes-the-object-pointer-not-the-data
title: a bytearray bound to a C pointer parameter passes the object pointer, not the data
summary: >
  `pipe(b)` for `b = bytearray(8)` and an imported `unistd.h` returns 0, creates
  real fds, and leaves `b` all zeros -- then the next use of `b` SEGFAULTS. pxx
  passes the TPyBytes OBJECT POINTER, so the callee reads and writes the
  instance's own header instead of the buffer. Measured from the callee's side by
  handing a 40-byte bytearray of 0xAA to `write(1, b, 24)`, and the three words
  map onto TPyBytes field for field:
  `d0 de 53 00 00 00 00 00` = the VMT pointer, `28 00 00 00 00 00 00 00` = FLen
  (40, plus padding), `48 00 80 b0 23 73 00 00` = FData, the heap pointer the
  callee actually wanted. So a C function that READS sees a VMT pointer and a
  length where it expected bytes, and one that WRITES destroys the VMT: `pipe`
  put fd 3 and fd 4 over it, and the next dispatch on the object jumped through
  0x400000003. THIS IS THE LIVE BLOCKER ON THE
  LEKKERZEILEN WINDOW PATH: the pxx platform backend is built on exactly this
  shape -- SDL_PollEvent(self._event_buf), SDL_GL_GetDrawableSize(h, self._wbuf,
  self._hbuf), glGetShaderiv(shader, pname, buf) -- and `--m0` now opens a window,
  brings up a real GL 3.3 context, prints the renderer and version strings, and
  dies in the first `win.size`.
track: N
type: bug
prio: 80
owner: unassigned
status: backlog
---

## The reproducer, six lines

    import "/usr/include/unistd.h"

    def first4(buf):
        return list(buf[0:4])

    b = bytearray(8)
    pipe(b)
    print("%s" % str(first4(b)))

`pipe` returns 0 and two real fds exist. `b` is still `[0,0,0,0,0,0,0,0]`.
`first4(b)` segfaults, in `pyvar_slice`.

## What is actually passed

Measured 2026-09-13 at c139938e5476, from the CALLEE's side, which needs no
debugger and cannot be confused with a pxx-side reading:

    b = bytearray(40)        # filled with 0xAA
    write(1, b, 24)          # let the C function tell us what it sees

    d0 de 53 00 00 00 00 00   -> 0x0053ded0
    28 00 00 00 00 00 00 00   -> 40
    48 00 80 b0 23 73 00 00   -> 0x00007323b0800048

Not 24 bytes of `0xAA`, which is what a data pointer would have produced. Those
three words are the TPyBytes INSTANCE, field for field against its declaration in
`compiler/builtin/pylib.pas:635`:

| offset | what | the bytes above |
| --- | --- | --- |
| 0 | the VMT pointer (pxx class layout) | 0x0053ded0, a data-segment address |
| 8 | `FLen: Integer`, plus 4 bytes of padding | 40 |
| 16 | `FData: Pointer` | 0x00007323b0800048, a heap address |

So the thing passed is the OBJECT POINTER, and the pointer the callee wanted is
sitting 16 bytes into what it was given. `PXXDBG=n.locals` agrees from the other
end: `b` is `tk=6 rec=100`, a class-typed variable, not a buffer.

**Two readings were checked against each other, and the first one I wrote was
wrong.** The initial claim was "a two-word {data pointer, length} descriptor",
which fits the first two words and is false. Three things separate the readings
and each is cheap:

- **The second word was re-asked at a different length.** The first run used a
  16-byte bytearray and printed 16 — and 16 is also `SizeOf(Variant)`, so at that
  length "this is a length" and "this is a variant header" are the same
  observation. Only the 40 separates them.
- **The first word did not move between the two runs**, staying 0x0053ded0 for
  both a 16-byte and a 40-byte bytearray. A data pointer changes with the
  allocation; a VMT pointer does not, because it belongs to the class.
- **The third word is a heap address** and is where the 0xAA bytes actually live.

A reading that explains two words out of three, with the third dismissed as
"whatever follows it", is the shape of this mistake.

## Why the symptom is a crash far away, and why it looks like a slice bug

The write lands on the instance header, not on the data:

| callee writes | effect |
| --- | --- |
| 0 bytes (`read(fd, b, 0)`) | nothing; `b` is fine afterwards |
| 8 bytes (`pipe`) | the instance's VMT POINTER becomes 0x0000000400000003 (fd 3, fd 4) |

So the bytearray's own bytes are never touched -- `-dPXX_HEAP_DEBUG` shows no
free, and `-dPXX_OBJTRACE` shows no release. The damage is to the handle. The
first code that follows the pointer is where it dies, which in lekkerzeilen is
`struct.unpack("<i", bytes(buf[off:off + 4]))` inside `_i32`, so the stack shows
`_i32 -> pyvar_slice` and the slice is innocent.

**A module-level use right after the call can look healthy.** `list(b)` and
`len(b)` at module level survived in three probes -- that path does not follow the
clobbered word -- and passing the same `b` to any function crashes. A probe that
only re-reads the buffer at module level therefore reports the call as working,
which is how this shape got written into a whole backend.

## Where the fix goes, named down to the arm

`IRLowerCallArg` (`compiler/ir.inc:4946`) is a sequence of
argument-kind x parameter-kind arms, each `Exit`ing with the right lowering. The
promo block around `compiler/ir.inc:5660-5720` is the worked example to copy, and
it already documents the trap this one shares: **`TypeIsOrdinal` includes
`tyPointer`**, so an arm written for ordinals also matches a `Pointer` parameter
and hands the callee a value where it wants an address. That comment records a
segfault found only by reading the argument's source node.

The pieces all exist:

- **The argument predicate**: `IRNodePyBytesRec(n)` (`compiler/ir.inc:8148`)
  returns the rec id when `n` is a TPyBytes and -1 otherwise. Confirmed against
  `PXXDBG=n.locals`, which reports a module-level `bytearray(8)` as
  `tk=6 rec=100` -- tyClass, TPyBytes. **It is DECLARED AFTER IRLowerCallArg**, so
  either move it, forward-declare it (ir.inc already carries 19 forward
  declarations), or inline the three lines; do not quietly duplicate it.
- **The parameter predicate**: `Procs[cpi].Params[pathIdx].TypeKind = tyPointer`
  and `not ...IsRef`.
- **The gate that keeps this out of every other caller's way**:
  `ProcExternal[cpi]` (`compiler/defs.inc:4405`). Passing a TPyBytes to a pxx
  routine declared with a `Pointer` parameter hands over the object pointer today
  and something in `lib/**` may want that; an external C symbol cannot.
- **The value**: `TPyBytes(o).FData`. Cleanest as a pylib entry point so the
  knowledge stays beside the class -- `function pybytes_cbuf(o: TObject): Pointer`
  returning `FData` for a TPyBytes and `Pointer(o)` otherwise, guarded at the call
  site with `FindProc('pybytes_cbuf') >= 0` the way the promo arms guard theirs, so
  a program with no pylib is untouched.

**ALL THREE SPELLINGS PASS THE SAME THING, WHICH I ASSERTED AS TWO SHAPES BEFORE
MEASURING IT.** The first version of this section said a module-level `bytearray`
is statically TPyBytes while lekkerzeilen's `self._wbuf` -- a FIELD -- arrives as a
VARIANT, and that an arm keyed on `IRNodePyBytesRec` would therefore fix the probe
and not the program. Measured: global, FIELD and PARAMETER all hand the callee the
identical three words (VMT 0x53ded0, FLen 40, FData), and the crash-on-next-use is
the same for all three. So it is one shape and one arm, and the claim was a
prediction about the frontend's typing wearing a measurement's clothes.

**But write the fixture with all three spellings anyway**, because the reason they
agree is not established: the parameter case may be typed TPyBytes (in which case
one class-keyed arm serves it) or may be a variant that happens to reach the same
lowering (in which case a class-keyed arm misses it and the row goes red). The
three rows cost nothing and they decide which it is.

What the parameter wants is `TPyBytes(o).FData`. The length the callee needs
travels separately in C (`write(1, buf, n)`, `SDL_PollEvent` knows its own struct
size), so nothing is lost by passing only the data pointer -- but `bytes` and
`bytearray` are ONE class here (`FIsByteArray` is a runtime tag, see the comment
at `pylib.pas:639`), so a refusal for the immutable spelling cannot be decided
from the static type. Three options, and the fork is worth settling before the
fix: pass FData for both and let a callee corrupt an immutable `bytes`; refuse at
run time on `FIsByteArray = False`; or refuse nothing and document it, which is
the `NilPy is UPWARD compatible` answer and is what the same file already chose
for mutating a `bytes`.

## Not established

Whether `bytes`, `str`, `list` and `array` arguments take the same route (only
`bytearray` was measured, and since `bytes` and `bytearray` are one class the
first of those is near-certain and still unmeasured); whether a C parameter
declared `void *` versus `int *` versus `char *` differs; and exactly which later
operation dereferences the clobbered VMT -- the crash is reached by passing the
object to any function, and `len()`/`list()` in place survive, but the dispatch
that dies was not isolated.

## Why it is ranked here

Counted in `lekkerzeilen/platform/_pxx.py`, 2026-09-13: **20 call sites hand a
bytearray to a GL or SDL function.** The list is not a measure of effort and must
not be read as one -- it is ONE coercion and one fix -- it is a statement about
what is REACHABLE:

    glGenBuffers / glGenVertexArrays / glGenTextures /
    glGenFramebuffers / glGenRenderbuffers          -> you cannot create anything
    glDeleteBuffers / ...VertexArrays / ...Textures /
    ...Framebuffers / ...Renderbuffers              -> you cannot destroy it either
    glGetShaderiv / glGetProgramiv                  -> no compile or link status
    glGetShaderInfoLog / glGetProgramInfoLog        -> no diagnostics when it fails
    glReadPixels                                    -> no capture
    SDL_PollEvent                                   -> no event loop at all
    SDL_GL_GetDrawableSize                          -> no viewport
    SDL_OpenAudioDevice                             -> no audio

Every `glGen*` entry point returns its new name THROUGH a buffer, so until this is
fixed nothing can be drawn under pxx -- not a triangle, because a VAO cannot be
created. That is the claim, rather than "20 sites are blocked": the four-walls
lesson in CLAUDE.md is that a count of units blocked is not a count of work, and
one shared coercion showing up twenty times is exactly the histogram that lesson
describes. What makes this prio 80 is that it sits across EVERY route out of the
driver, not that it appears twenty times.

## See also

- `umbrella-lekkerzeilen-compiles-and-runs-under-nilpy` -- add as a blocker.
- `task-b-write-the-lekkerzeilen-pxx-platform-backend` -- the backend that is
  built on this shape.
