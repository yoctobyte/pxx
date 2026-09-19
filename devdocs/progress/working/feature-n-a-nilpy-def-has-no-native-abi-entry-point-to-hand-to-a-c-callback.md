---
track: N
prio: 55
type: feature
owner: frankb-8e
blocked-by: []
summary: "MECHANISM: a NilPy `def` is reachable only through a Python callable carrier and through `$pycallwrap_<pi>`, whose signature is all-Variant. A C or Pascal callback slot wants a routine whose ABI matches ITS declared signature, and no such entry point is emitted for a def, so there is nothing to take the address of. This SPRINGS wherever a def must be handed to code pxx did not generate -- an SDK callback, a qsort comparator, a signal handler. It is why examples/esp32/nilpy-hw-c3 keeps its timer callback in Pascal and POLLS a counter from Python."
status: working
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

## Acceptance

The ESP demo stops polling: its timer callback is a `def` in `main.npy`, and
`main.expected` still matches what CPython prints for the stubbed program.
Cheaper host-side proof first -- a def handed to a Pascal `procedural`
parameter of a non-Variant signature, called from Pascal, returning the value
the def computed.
