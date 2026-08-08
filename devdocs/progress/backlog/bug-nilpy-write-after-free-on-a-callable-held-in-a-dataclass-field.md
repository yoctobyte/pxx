---
track: N
prio: 50
type: bug
summary: "SILENT->CRASH: a callable stored in a `Callable` field outlives its object — `-dPXX_HEAP_DEBUG` reports WRITE AFTER FREE and the recycled block comes back as a list's element storage, so calling the field jumps into a variant array. This is what blocks uforth now."
---

# A callable in a Callable field is freed while the field still holds it

uforth, after the pyeval mixed-param fix, segfaults compiling `IO.UFO`:

```
pxx-heap: WRITE AFTER FREE in 0x00007fffd8089908      (-dPXX_HEAP_DEBUG)
SIGSEGV, PC = 0x00007fffd7f069c0                       (a HEAP address)
```

Call chain, symbolised through the `.map` (`readelf` is blind on pxx binaries):

```
VM.interpret_file -> VM._interpret_current_source_line -> VM.exec_token
  -> VM.compile_token -> pyvar_callv1 -> <jump into the heap>
```

`compile_token`'s `word.native(self)` on an IMMEDIATE word (uforth.py:906).

## The tell

`pyvar_callv1` reached its LAST arm — `f1 := TPyCallFn1(payload); f1(a0)` — which
runs only when `PyCallableObj` returns nil, i.e. the payload's magic matches
neither a closure nor a bound-fn. Dumping the payload shows why:

```
0x7fffd7f069c0: 0x00007fffd80e12a8  0x0000000000000007
0x7fffd7f069d0: 0x00007fffd80e0e10  0x0000000000000007
```

Alternating {pointer, 7} — an array of 16-byte VT_OBJECT variants, i.e. some
TPyList's element storage. The callable's block was FREED and the allocator
handed it to a list; the magic is gone, so the tag test falls through and the
call jumps into the variant array.

BEGIN, WHILE, IF and THEN dispatch correctly first; REPEAT is where it dies.
Nothing distinguishes them in uforth — all four are
`vm.define_word("X", native=w_x, immediate=True)` — which is itself evidence for
recycled memory rather than a bad lowering of one word.

## NOT the pyeval mixed-param fix

Measured, not assumed. With the bridge instrumented to print every variant
argument it marshals, the WRITE AFTER FREE is reported on **line 1 of the
program's output, before the first mixed host call happens at all**, and the
freed address matches none of the seven objects that later travel through it
(nor is any within a page of it). The marshalling buffer there is also
deliberately non-owning now (a raw `TPyRec`, not a managed `Variant`), so that
path adds no release.

The isolated repros of the same shape — a closure through the mixed host bridge,
stored in a `Callable` dataclass field and called afterwards — all pass against
the CPython oracle (`test/test_nilpy_pyeval_host_mixed_params.npy`). uforth had
simply never executed this far before.

## Where to start

The suspects are the four-places variant OBJECT-tag list
([[project_variant_object_tag_list_lives_in_four_places]]): a retain missing on
ONE of the paths that stores a callable variant into a field leaves the field
holding a borrowed reference, and the owner's release then frees it. `native`
arrives as VT_PYCLOSURE (tag 9) in uforth's case — measured — so check the
closure arm specifically, and check it in the CONSTRUCTOR store as well as the
plain field store, which are different lowerings
([[project_nilpy_class_attribute_lowering_matrix]]).

`-dPXX_OBJTRACE` then `grep <addr>` names the retain/release pairs, but note it
is BLIND to plain GetMem, so confirm the closure object is actually traced
before trusting an empty result.

## Gate

`make test-uforth` past `IO.UFO`, plus a `.npy` that keeps a closure alive only
through a `Callable` field across enough allocation to force block reuse,
oracle-diffed, plus `-dPXX_HEAP_DEBUG` clean on it, plus the per-fix loop.
