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
  0x400000003. FIXED 2026-09-13 and it took TWO arms, not one: a NAME and a FIELD
  are statically a TPyBytes and divert in IRLowerCallArg through pybytes_cbuf; a
  PARAMETER and a CALL RESULT arrive as a tyVariant that the frontend has already
  rewritten, and divert in PyCoerceCallableArgsIn through pyvar_cbuf. The second
  arm is the one lekkerzeilen needed. Seven-row fixture, all seven red under pin
  v408.
track: N
type: bug
prio: 80
owner: frank-user
status: done
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

## RESOLUTION 2026-09-13

Two code sites, because the defect has two shapes and each mechanism is blind to
the other's. Landed with `test_nilpy_a_bytearray_reaches_a_c_pointer_parameter`
(7 rows, every one of them red under pin v408).

**`compiler/builtin/pylib.pas`** -- two entry points, so the knowledge about
TPyBytes stays beside the class:

    function pybytes_cbuf(o: TObject): Pointer;      { FData, or Pointer(o) }
    function pyvar_cbuf(const v: Variant): Pointer;  { tag 7 -> the above;
                                                       else the raw payload }

`pyvar_cbuf` returns the payload word for every non-bytes tag, which is exactly
what the lowering handed over before, so the answer changes for a TPyBytes and
for nothing else.

**`compiler/ir.inc`, `IRLowerCallArg`** -- the STATIC arm, keyed on
`IRNodePyBytesRec(argAST) >= 0`, gated on `ProcExternal[cpi]` and a non-ref
`tyPointer` parameter. Placed with the variant unboxes and ahead of the promo
block, for the reason that block's own comment gives: `TypeIsOrdinal` counts
`tyPointer`.

**`compiler/pyparser.inc`, `PyCoerceCallableArgsIn`** -- the DYNAMIC arm, and the
one the demo needed. That routine already rewrote EVERY variant argument bound to
a `Pointer` parameter into `pyvar_callable_ptr(v, '<param>')`, on the reading that
a pointer parameter is a callback slot. For an EXTERNAL C callee it is a data
pointer, so the rewrite now goes through `pyvar_cbuf` there instead. Two
diagnostics are deliberately given up for an external callee: None becomes a NULL
pointer rather than a named TypeError (NULL is what C means by an absent buffer),
and a builtin type passed there is no longer refused by name. Neither is a
callback question.

### The measurement that went wrong, and the hedge that saved it

The section above says *"global, FIELD and PARAMETER all hand the callee the
identical three words ... So it is one shape and one arm."* **The measurement is
right and the inference is wrong.** What the callee RECEIVES being identical says
nothing about how the frontend TYPES the argument -- all three were broken, by two
different routes, which is precisely why they looked alike. One arm fixed two of
the three.

What caught it is this ticket's own next paragraph, which refused to bank the
inference: *"write the fixture with all three spellings anyway, because the reason
they agree is not established."* Written as a hedge on a prediction, and it is the
only reason the parameter spelling got asked about at all.

The first reading of the RESULT went wrong the same way, in the opposite
direction. With the static arm alone, `pipe(b)` was fixed and
`write(1, passthru(b), 24)` was not -- so the note in the handover said the READ
direction was still broken and named `const void *` versus `int *` as the likely
cause. That reading is comfortable, mechanical and wrong: the probe for the read
direction happened to pass the buffer through a HELPER, so it varied the route and
the direction together. Re-asked with the direction held and the route varied,
**both directions fail through a parameter and both work through a name.** The
boundary was never read-versus-write. CLAUDE.md's *"does my probe reach the thing
under test BY THE ROUTE under test, and by no other?"* is the rule, and the
violation here was a single incidental `passthru()`.

### The bytes-versus-bytearray fork, decided

The section above left three options. **Chosen: pass FData for both spellings and
refuse nothing** -- the `NilPy is UPWARD compatible with CPython` answer, and the
one `pylib.pas` already took for mutating a `bytes`. `FIsByteArray` is a runtime
tag on one class, so a static refusal is not available anyway, and a runtime one
would refuse `write(1, b"hello", 5)`, which is correct code.

### Verified

- The 7-row fixture passes; under `stable_linux_amd64/default/pinned` (v408) all
  seven rows differ -- A-D print 0 where a written buffer gives 1, E/F/G return -1
  (EBADF: the fd never arrived) and the round-tripped bytes come back as zeros.
- A tyVariant arm in `IRLowerCallArg` was BUILT, measured UNREACHABLE for every
  shape constructible (the frontend rewrites first), and removed rather than
  shipped. Both surviving arms carry a pointer to the other.
- C frontend probe in the same shape (`write(1, b, 4)` from C) unaffected; the
  marshalling one-liner `x = "a" * 3` answers `aaa`.

### Residual, not this ticket

`bytes`, `str`, `list` and `array` arguments were never measured -- only
`bytearray`. `bytes` shares the class and so is covered; the other three are not
and nothing asks for them yet.
