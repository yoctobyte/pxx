---
slug: bug-n-a-callable-value-called-with-four-arguments-dereferences-a-variant-at-address-1
title: a bound-method value crashes when its method was not normalised to a variant return
summary: >
  ROOT CAUSE FOUND. `PyMethodUsedAsValue` decides whether a method is
  normalised to the function-object ABI by SCANNING TOKENS up to
  MainProgramTokCount -- so it cannot see a module that has not been appended
  yet. A method used as a value in a module compiled AFTER the one declaring it
  therefore keeps its inferred scalar return, and `PyMakeBoundMethod` hands its
  RAW address to a bridge whose TPyCbM0..M8 all return Variant. The callee
  leaves a Boolean in rax, the bridge retains rax as the result variant's
  ADDRESS, and `mov (%rax),%rcx` with rax=1 is the crash. Reduced to four
  files; lekkerzeilen's `Frustum.sees` is the live case.
track: N
type: bug
prio: 90
owner: unassigned
status: open
---

## The reduction

Four files. The shape is the point: `geom` declares the method, `early` imports
geom and only CALLS it, `late` imports geom and takes it as a VALUE. `early` is
what drags geom into the compile, so geom is compiled before `late`'s tokens
exist.

```python
# geom.py
class Box:
    def __init__(self, planes):
        self.planes = planes

    def sees(self, x, y, z, radius):
        for a, b, c, d in self.planes:
            if a * x + b * y + c * z + d < -radius:
                return False
        return True

# early.py
import geom
PLANES = [(1.0, 0.0, 0.0, 0.0), (0.0, 1.0, 0.0, 0.0)]
def probe():
    return geom.Box(PLANES).sees(1.0, 2.0, 3.0, 0.5)

# late.py
import geom
import early
def draw():
    box = geom.Box(early.PLANES)
    print("direct  ", box.sees(1.0, 2.0, 3.0, 0.5))
    sees = box.sees
    print("hoisted ", sees(1.0, 2.0, 3.0, 0.5))

# main.npy
import early
import late
print("early   ", early.probe())
late.draw()
```

CPython prints three lines. pxx at b46c98d433f1 prints `early True` and
`direct True`, then **rc=139** on the hoisted call.

**Collapse it into one module and it passes.** Put the hoist in the main
program and it passes. Put the hoist in the same module that first imports the
declaring one and it passes. Four such arrangements were measured and all four
are green -- which is exactly why this never showed up in a fixture. It is the
`normalise-dont-special-case` ordering rule again: the arrangement everyone
writes is the one that works.

## The mechanism, end to end

`PyMethodUsedAsValue` (pyparser.inc) is a token scan:

```pascal
j := 1;
while j < MainProgramTokCount do ...   { `<something>.nm` not followed by ( or = }
```

`MainProgramTokCount` is re-pointed to the END OF THE MODULE BEING COMPILED, so
the scan's population is "every module appended so far". A use in a later
module is invisible, the method is not normalised, and its inferred return type
stands. Its own comment already records what that costs: *"Without it the pair
carried a method whose result came back in a register while the caller expected
the hidden-destination convention: a bound method returning a value crashed,
and one returning None happened to work."* The mechanism was understood; only
its blind spot was not.

`PyMakeBoundMethod` then emits `AN_PROCADDR` of the method RAW and passes
`Procs[mpi].IsFunc` -- a two-way function/procedure flag where a THREE-way
distinction is needed: variant-returning function, scalar-returning function,
procedure. The sibling path for plain defs gates on exactly the missing case
(`Procs[pi].RetType <> tyVariant` -> `PyGetOrMakeCallableWrapper`); the
bound-method path never got that gate.

`PyBoundPairCallKwBody` casts the code pointer to `TPyCbM4` (`: Variant`),
calls it, and the emitted caller then does `call <retain thunk>` on rax --
`mov (%rax),%rcx; cmp $6; cmp $7`. rax is `1`, i.e. `True`.

## Static proof, no timing involved

In lekkerzeilen, `App._draw_scene` contains exactly one `pybound_new_sig` and
one `pyvar_callv4`, and pushes `0x617379` as the code pointer -- which the map
names `Frustum.sees`. `Frustum.sees` ends in
`movzbq -0x29(%rbp),%rax; leave; ret`: a zero-extended BYTE. Nine modules
import math3d and `app.py`, which holds `sees = frustum.sees`, is not the first
of them.

## Where to fix it

`PyMakeBoundMethod`. Making the scan see later modules is not possible -- they
have not been tokenised -- so the adaptation belongs where the callee is known,
which is the same conclusion `PyGetOrMakeCloneThunk` reached for the clone
trampoline and states in its own header. Synthesize a cached
`function $pyboundwrap_N(recv: Pointer; const a0..: Variant): Variant` whose
body is `Result := TCls(recv).meth(a0, ...)`, on the existing pending-lambda
queue with a new `PyPendLamTok` sentinel (-1 and -2 are taken by the
callable-value wrapper and the clone thunk). Then pass the wrapper's address to
`pybound_new_sig` instead of the method's.

Widening every method unconditionally would also work and costs boxing on every
bound-method call; the wrapper is local and pays only where the ABI actually
differs.

## Gate

`make test-nilpy` + self-host byte-identical, plus the four-file reduction
above wired as a fixture -- and it must stay a MULTI-MODULE fixture with the
value-use in the later module, because every single-module spelling passes on
the unfixed compiler.

## Earlier notes (kept)

## Why this is NOT the heap bug it looks like

**pxx's allocator never calls glibc malloc.** `builtinheap.pas` takes 256 MiB
anonymous-mmap arenas with its own 8-byte size header. So
`malloc(): unsorted double linked list corrupted` names GLIBC's allocator --
the C side: SDL, mesa, libc. That framing cost a build: `-dPXX_HEAP_DEBUG`
(poison `$DD`, a 1024-block quarantine, `PXXDbgIsPoisonWord`) instruments
**PXXAlloc/PXXFree only**, so against this it runs, reports nothing, and the
program still dies. An instrument correct about the other heap.

**MALLOC_PERTURB_ is what separated them.** With freed memory filled with
`0xA5`, the run stops presenting as heap corruption and presents as the
address-1 dereference above. **1 is not a perturb-derived value** -- a variant
read out of freed memory would carry VType `0xA5A5A5A5A5A5A5A5`. It is a real
bad pointer, and the heap damage is what happens after something writes
through it.

## Why it was not reachable until today

The world path used to die at ~2.95s into the frame loop on
`bug-n-a-dynamically-dispatched-call-fills-its-defaults-from-another-class-signature`
(fixed at accb99f3c). With that repaired it reaches ~5.7s and lands here.
Same shape as
`bug-n-a-run-time-dispatched-call-s-result-is-coerced-to-an-integer`: a fix
that makes calls complete exposes the layer the incomplete call was hiding.

**MEASURED 2026-09-14: NOT accb99f3c.** The control was run twice over. A
compiler built at `accb99f3c^` (55cdf94233a9) and a lekkerzeilen built from the
same sources reproduce the world-path fault identically under valgrind; and
disassembled, both binaries carry the same call sequence at the faulting site.
See `done/bug-n-a-class-reference-receiver-walks-rtti-off-a-non-instance`.

**That same run also showed this ticket names the WRONG FRAME.** Under valgrind
the program dies earlier, on the LOADER thread, at arity 0, inside
`__pxxInheritsFrom` reached from `App._bucket` -- a classref receiver walking
RTTI off a non-instance. That was a separate bug and it is now FIXED. The
gdb chain recorded above is a DIFFERENT fault: main thread, arity 4,
`App._draw_scene`, a bad ADDRESS rather than a bad class pointer. It IS still live: with the
classref fix in, lekkerzeilen now loads the world, renders the 512x512 chart
in 3.2 s, reaches the frame loop -- and dies here, same instruction, same
`rax=1`, on thread 1, with `PyBoundPairCallKwBody+0x2915` under
`PyBoundPairCallKwBody+0x111`. So this ticket is the world path's REMAINING
wall, not a duplicate of the one that was fixed. The slug's "four arguments"
is accurate for this observation and was never corroborated by the valgrind
one, which was a different bug entirely.

## Family

`{VType=7, Payload=1}` is the exact signature the dynamic-default bug produced:
a bind that fails and hands back a variant carrying 1. A `const Variant`
parameter travels BY ADDRESS, so a caller that passes such a variant's PAYLOAD
where its ADDRESS belongs yields precisely rax=1. Suspect the `{code, recv}`
pair's receiver slot, or a rung passing a value where the ABI wants an address.

The forwarders were read and are NOT the fault: `pybound_callv0..8` pass the
global `pynone` by const for unused slots, and `pybound_pair_call` forwards
a0..a7 plus two typed-nil lists. All addresses, none synthesised.

## Where to look

`PyBoundPairCallKwBody` (pylib.pas), specifically the argument array `av[0..7]`
and the indirect call rungs. Note it also reads the PYSIG defaults array
(`sr^.Dflts`, `av[i] := PVariant(NativeInt(dp) + i * 16)^`) and raises on
`PYSIG_DFLT_UNSET`; a slot filled with a bad value rather than left unset would
not trip that guard.

## Measured negatives, so nobody repeats them

- A library-owned `const char*` return is NOT adopted as a managed AnsiString:
  `zlib.zlibVersion()` called 200000 times in a loop answers correctly, rc=0.
  That retires the simplest form of the bad string->PChar hypothesis.
- `--open-water` survives a 150s timeout (rc=124) on the same binary, so this
  is specific to the world path. The only things the world path adds are the
  geodata load and a 512x512 chart render.
- valgrind is installed now; a memcheck run over this program is very slow
  (13 threads) and had not reached the loop when this was filed.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` calling a callable
VALUE at arity 4 through a stored attribute. The arity matters: `pybound_callv4`
exists because arity 4 had no member and had to be added
(bug-nilpy-a-four-parameter-lambda-segfaults-when-called), so 4 is the rung
with the least mileage on it.

## Log
- 2026-09-14 -- found hunting lekkerzeilen's world-path fault, after accb99f3c
  moved the failure past the dispatch bug. Owner's steer (heap re-use / bad
  string-PChar conversion) is what prompted the glibc-vs-pxx-heap distinction
  that reframed it.
