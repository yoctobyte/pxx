---
slug: bug-n-a-callable-value-called-with-four-arguments-dereferences-a-variant-at-address-1
title: a callable value called with four arguments dereferences a variant at address 1
summary: >
  lekkerzeilen's world path dies in the frame loop inside the bound-pair call
  bridge, reading a variant's VType through a pointer whose value is 1. The
  faulting instruction is `mov (%rax),%rcx` with rax=1, followed by `cmp $6` /
  `cmp $7` -- a VT_STRING/VT_OBJECT tag dispatch on a variant that was passed
  by ADDRESS and received the value 1 instead. Presents WITHOUT MALLOC_PERTURB_
  as `malloc(): unsorted double linked list corrupted`, which sent the first
  investigation at the heap; the heap damage is downstream of writing through
  this pointer, not the cause.
track: N
type: bug
prio: 90
owner: unassigned
status: open
---

## The chain, fully resolved

`setarch -R gdb` with `MALLOC_PERTURB_=165 MALLOC_CHECK_=3`, addresses resolved
against the binary's own `.map`:

```
App.run            + 0x1bf4d
App.render         + 0x9448
App._draw_reflection + 0x80d9
App._draw_scene    + 0xdf74
pyvar_callv4       + 0x1a9
pybound_callv4     + 0x2a0
PyBoundCallV       + 0x220
pybound_pair_call  + 0x194
pybound_pair_call_kw + 0x1f1     <-- faults here
```

Fault: `mov (%rax),%rcx` with **rax = 1**, then `cmp $0x6,%rcx` / `cmp $0x7,%rcx`.

`pybound_pair_call_kw` is a three-line wrapper (retain / body / release), so at
`-O2` the +0x1f1 site is `PyBoundPairCallKwBody` inlined into it.

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

**NOT yet established whether this site is pre-existing or was perturbed by
accb99f3c**, which did touch shared RTTI emission (`EmitMethInfo`'s param
block grew by one word). That control is a compiler rebuild plus a ~2m45s app
build and has not been run. Do not assume either way.

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
