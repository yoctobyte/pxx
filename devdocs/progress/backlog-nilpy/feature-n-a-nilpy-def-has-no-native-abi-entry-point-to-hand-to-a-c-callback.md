---
track: N
prio: 85
type: feature
owner:
blocked-by: []
summary: "PARTLY DONE. A NilPy `def` compiles all-Variant -- by-reference Variant parameters, the result on the Variant hidden destination -- so it can never match a native procedural signature. `PyGetOrMakeCallbackThunk` now synthesizes `$pycbthunk_<def>_<sig>` carrying the SLOT's signature and stores ITS address, keyed on the PAIR because one def can go to two differently-shaped slots. That covers a procedural PARAMETER, including on an `external cdecl` routine. WHAT REMAINS, and it is what the ESP demo actually needs: the same def assigned to a procedural FIELD takes no such path and segfaults with NO diagnostic, because the coercion lives in PyCoerceCallableArgsIn, which sees arguments only. SPRINGS wherever a callable reaches native code through a field or a struct rather than an argument list. The ISR question -- boxing into Variants allocates -- is deliberately out of scope and needs its own contract."
status: backlog
---

# A NilPy def has no native-ABI entry point to hand to a C callback

## What is missing

`8826e6aec` made a **Pascal** routine handed from NilPy into a Pascal
procedural parameter work: `PyCoerceCallableArgsIn` now recognises a
procedural-parameter slot, recovers the named routine out of the carrier and
stores its plain address. That mechanism recovers an address that **already
exists**.

For a NilPy `def` there is no such address. The two things a def can be
reached through are:

- the callable carrier (`pybound_new_sig` / `pybound_new_star` /
  `pybound_new`) -- a heap record, not code;
- `$pycallwrap_<pi>`, synthesised by `PyGetOrMakeCallableWrapper` -- real
  code, but its signature is **all Variant**, because it exists so a callable
  can be invoked without knowing its shape.

A C callback slot declares a shape: `void (*)(void*)`, `int (*)(const void*,
const void*)`. Neither of the above fits it, and `ProcSigCompatible` correctly
refuses the wrapper for exactly that reason.

## What it costs today, in a demo we ship

`examples/esp32/nilpy-hw-c3/main/main.npy` says it in its own header:

> *"A def's address cannot be handed to C as a function pointer today (an
> unannotated value arriving at an external Pointer parameter is taken as a
> data buffer, deliberately). So esptimer.pas owns the callback and the
> counter, and this program ASKS how many times it has fired."*

So the hardware demo's Python half **polls**. The ESP-IDF timer callback is
Pascal. The sentence we would like to be able to say about that demo -- *a
Python function runs in the interrupt path* -- is the one this blocks.

## The shape of a fix, and it is a SPLIT

A thunk: emit, per `(def, target signature)` pair that is actually demanded,
a small native-ABI routine whose parameters are the slot's declared ones, that
boxes them into Variants and tail-calls the existing `$pycallwrap_<pi>`. The
address of THAT is what goes in the slot. The demanded pairs are known at the
coercion site, which already has both the def and `ProcParamProcSig`.

**Two halves, two owners, and they are not the same job:**

- **the carrier half is frankH's** -- their words, 2026-09-20: *"Come back to
  me before changing how the carrier is BUILT -- that is mine ... Reading Code
  out of it, or adding a thunk beside it, is entirely yours."* If materialising
  the thunk address requires it to live IN the carrier, that part is theirs.
- **the thunk half** -- emitting the routine and wiring the coercion site --
  sits beside `PyCoerceCallableArgsIn`, which `8826e6aec` already owns.

Whoever takes this should agree the boundary with frankH first rather than
guess which side a given change is on.

## Open questions this ticket does NOT decide

- **Who keeps the def alive?** A slot holding a thunk address does not retain
  the carrier, so a def whose only reference is a C callback slot can be
  collected. A C callback slot has nowhere to put an owning reference.
- **Does it re-enter safely?** The ESP case is an ISR. Boxing into Variants
  allocates, and an allocating callback in an interrupt path is its own
  decision -- possibly the answer for ESP is a restricted thunk that refuses
  to allocate, and possibly it is that the ISR case is out of scope and the
  demo's honesty is the right outcome.

Both are reasons this is a feature rather than a bug: nothing is producing a
wrong answer today, the refusal is deliberate and documented at the call site.

## The host-side repro, measured 2026-09-20 (compiler f99f37bcebe2)

Already reduced, and it is the positive control for whatever lands. Against
`test/nilpy_units/procslot.pas`, which `8826e6aec` already ships:

```python
import 'procslot.pas' as ps


def mymaker(laden, room):
    return laden * 100 + room


k = ps.MkKind(mymaker)
print(ps.CallItFromPascal(k))
```

Compiles, with the diagnostic `8826e6aec` added firing at exactly the right
line and naming this ticket's mechanism:

```
pascal26:8: warning: Nil Python: mymaker does not have the signature of
procedural parameter 'f', so the callable object is stored rather than a code
address -- calling through that slot will crash. A def compiles all-Variant
and needs a native-ABI thunk, which is not built yet.
```

Then **segfaults** (exit 139). CPython prints `502` for the same program with
the Pascal unit stubbed. So the diagnostic is honest, the crash is the thing to
remove, and `502` is the oracle. Note the warning is a WARNING and not an
error deliberately: refusing here would break programs that store a callable
they never call through that slot.

## The boundary, read 2026-09-20 -- this needs NO carrier change

The ticket above says "if materialising the thunk address requires it to live
IN the carrier, that part is theirs". Reading pyparser.inc, it does not, and
the reason is that **three** synthesised-adapter sites already exist on one
pending-lambda queue and none of them touches a carrier:

| synthesiser | emits | params | result |
| --- | --- | --- | --- |
| `PyGetOrMakeCallableWrapper` | `$pycallwrap_N` | all Variant | Variant |
| `PyGetOrMakeCloneThunk` | `$pyclonethunk_N` | one `Pointer` | none (a procedure) |
| `PyGetOrMakeBoundRetWrapper` | `$pyboundretwrap_N` | p0 keeps the method's OWN type + `ProcParamRecId` | Variant |

`PyGetOrMakeCloneThunk` **is already this ticket's shape** -- a native-ABI
thunk for a def, built because `__pxxclone`'s trampoline has a fixed
non-Variant contract. `PyGetOrMakeBoundRetWrapper` proves a synthesised
routine can take a non-Variant parameter type and carry class identity. The
two together are a C callback thunk, with the types coming from
`ProcParamProcSig` instead of from a method.

The `bStart = -1` body builder loops over the synthesised proc's own
parameters and relies on the ordinary argument/return coercion, so
`<target type> -> by-ref Variant` in and `Variant -> <target result>` out
should need no new runtime. **That sentence is a READ of the code and not a
measurement** -- it is the first thing to check by building.

### The one genuinely new thing

All three cache by the real proc ALONE (`'$pycallwrap_' + realPi`,
`'$pyclonethunk_' + realPi`, `'$pyboundretwrap_' + mpi`), which is safe for
them because their signature is a function of that proc. It is NOT safe here:
one def handed to two different callback slots needs two thunks, so the key
must be **(realPi, target signature)**, and the queue currently carries only
`PyPendLamWrapReal`. Either derive the name from the target's pi, or add a
second parallel array.

## MEASURED 2026-09-20 -- half the read was WRONG, and it returned garbage

The sentence flagged above as "a READ of the code and not a measurement" --
that `<target type> -> by-ref Variant` in and `Variant -> <target result>` out
both come free -- **was right in one direction and wrong in the other**, and
the wrong one produced a plausible wrong answer rather than a crash.

Built the smallest thunk and read the IR before writing the feature, which is
the only reason this was caught here instead of in a fixture:

```
1: load_sym a0 tk=1
2: var_store tk=22        <- Integer -> by-ref Variant. INBOUND: free, as read.
4: arg (address of it)
14: call <the def> tk=22
15: terminate             <- NO STORE. OUTBOUND: not free.
```

`PyCompileLambdaBody` creates `$pyresult` under `if Procs[procIdx].RetType =
tyVariant`. A thunk returns the SLOT's type, so `RetSymIdx` stayed -1, the
`AN_EXIT` that the `bStart = -1` path does build had nowhere to store,
`EmitProcEpilog(-1)` emitted nothing, and the result register held whatever the
call left. `ps.CallItFromPascal(k)` printed **1637568216** where CPython prints
502 -- the failure this seam's own sibling comment warns about, and worse than
the SIGSEGV it replaced.

One arm beside that condition fixes it: a synthesized proc that IS a function
and does NOT return Variant gets a result symbol of its own return type. The
IR then ends `call <def> tk=22` / `call pyvar_to_int tk=13` / `store_sym
$pyresult tk=1`, and the repro answers 502.

**Blast radius checked rather than asserted, because it is shared machinery:**
the three sibling synthesizers cannot reach the new arm. `$pycallwrap_` and
`$pyboundretwrap_` return tyVariant and take the pre-existing arm;
`$pyclonethunk_` is a PROCEDURE (`IsFunc` False).

### Re-estimate

Still small -- one synthesizer, one guard, one arm in the body compiler. The
read being half wrong did not change the size, only the shape.

## Two things the guard got right for the wrong reason, and one it got wrong

- **Written from expectation, caught by reading the builder.** The "closes over
  nothing" test was first written as `ASTKind[recvArg] = AN_NIL`.
  `PyMakeFuncValueFor` actually builds the receiver as `AN_INT_LIT 0` typed
  tyPointer. That guard would have refused every carrier and **silently
  disabled the whole feature** -- born red, in the direction that produces no
  signal at all. An assertion written from what a value *should* be pins the
  expectation, not the code.
- **A capturing nested def is excluded by CONSTRUCTION, not by the guard.** The
  lambda lift appends captured state as extra parameters, so `outer.inner` has
  3 params (`22 22 13`) against the slot's 2 and fails both the arity test and
  the all-Variant test. The mechanism that makes it a closure is what makes it
  fail -- a better exclusion than the one written by hand.
- **A bound method is excluded by the guard**, via the live receiver, and keeps
  the warning.

## Four targets, not one -- this is an ABI feature and x86-64 is the blind spot

A thunk exists entirely to bridge two calling conventions, so measuring it only
on the host would be measuring the one target where the dev loop, `gate.sh
quick` and the pin all already agree. Compiled and RUN under qemu, same
fixture, same `.expected`:

| target | result |
| --- | --- |
| x86-64 | matches |
| i386 | matches |
| aarch64 | matches |
| arm32 | matches |

i386 matters most of the four: 32-bit, a different `Double` return convention,
and the row this fixture carries that answers `3.75` goes through it.

## A pre-existing gap found here and deliberately NOT fixed

A capturing nested def handed by name gets **no warning at all**:
`PyCarrierNamedProc` answers -1 for that carrier shape, so the warn arm added
in `8826e6aec` never fires. It segfaults identically on pin v412 and at HEAD,
so it is unchanged behaviour and not introduced here. Recorded rather than
absorbed into this ticket's scope.

## WHERE THE ESP DEMO ACTUALLY BLOCKS -- measured 2026-09-20, and it is NOT
## where this ticket first said

Filed on the strength of `examples/esp32/nilpy-hw-c3/main/main.npy`'s header,
which says *"an unannotated value arriving at an external Pointer parameter is
taken as a data buffer, deliberately"*. That sentence is true and it is about a
DIFFERENT shape than the one that blocks. Measured at HEAD rather than quoted:

| a def reaches native code as... | today |
| --- | --- |
| a procedural PARAMETER, Pascal routine | works (thunk) |
| a procedural PARAMETER on `external cdecl` | works (thunk) -- `$pycbthunk_<n>_<n>` minted, `ptypes 17 17` |
| a bare `Pointer` parameter on `external` | taken as a DATA buffer, silently -- the header's sentence |
| **a procedural FIELD** | **silent SIGSEGV** |

`esptimer.pas` uses the last row, twice over: the user callback is the field
`TEspTimer.OnElapsed: TTimerProc`, and it crosses to the SDK as the `Pointer`
field `args.callback` of the struct handed to `esp_timer_create`
(`args.callback := Pointer(t.OnElapsed)`).

So the C-side crossing is NOT the wall this ticket assumed. The wall is that
`PyCoerceCallableArgsIn` -- the one place a callable value is coerced -- sees
ARGUMENTS ONLY. A field assignment never reaches it:

```python
s.two = two        # segfaults, no diagnostic
cb.MkTwo(two)      # works
```

**NEXT STEP for this ticket**, and it is the same mechanism one door along:
the field-assignment path needs the identical `ProcSigCompatible` / thunk
decision the argument path now has. Nothing about the thunk changes; what
changes is that a second site has to ask the question.

## Acceptance

The ESP demo stops polling: its timer callback is a `def` in `main.npy`, and
`main.expected` still matches what CPython prints for the stubbed program.
Cheaper host-side proof first -- a def handed to a Pascal `procedural`
parameter of a non-Variant signature, called from Pascal, returning the value
the def computed.

## Why this should not sink in the backlog (frankz-e5, 2026-09-20)

Relayed secondhand by frankuser, not heard firsthand: **the owner is interested
in this mechanism for a possible `ffsfs` demo** — a Python program handing a
compiled routine to C as a callback. Recorded here because an unowned ticket
with a ready next step is exactly what gets lost, and because a reader who
knows a demo wants it will rank it differently from one who reads it as a
frontend nicety.

The next step is a one-sitting job for a rested seat: the argument path asks the
`ProcSigCompatible`/thunk question and a **field assignment** does not.
`RecFieldProcSig(rec, field)` already exists. The four-row table above is the
measurement; nothing about the thunk changes.

## OWNER: ESP INTERRUPTS ARE A MUST-HAVE (2026-09-20, relayed by frankuser)

His word, relayed secondhand and marked as such: **must-have, not a demo caveat.**
Re-ranked 55 -> 85 on that basis; the number is his, not a seat's.

`examples/esp32/nilpy-hw-c3` POLLS a counter today, and it polls because a NilPy
`def` has no native-ABI entry point — this ticket.

**ONE CAPABILITY, THREE CONSUMERS. Say so before anyone builds half of it twice:**
1. **ESP interrupts** — the demo takes its timer callback in Python instead of polling.
2. **The field site** — frankb-8e's `2b28c3302` did the argument path; a procedural
   FIELD assignment still segfaults silently. `RecFieldProcSig(rec, field)` already
   exists; the four-row table is above. Unowned, one sitting.
3. **ffsfs** — a Python program handing a compiled routine to C as a callback
   (recorded in `abb2ae020`, also secondhand).

**The ISR half stays separate and is NOT this ticket**: boxing into Variants
allocates, and an ISR that allocates is a latent crash with good latency numbers.
A non-allocating restricted thunk (fixed arity, scalar-only, no Variant) is a
different contract. Delivering THIS ticket does not by itself let the demo stop
polling; the ISR path must be shown not to allocate.
