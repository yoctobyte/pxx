---
track: N
prio: 50
type: bug
summary: "SILENT->CRASH: a callable stored in a `Callable` field outlives its object — `-dPXX_HEAP_DEBUG` reports WRITE AFTER FREE and the recycled block comes back as a list's element storage, so calling the field jumps into a variant array. This is what blocks uforth now."
status: done
owner: claude-N
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

## RESOLVED 2026-08-08 — a promo LOCAL was cleared without ever being initialised

Not a refcount bug, and not the callable's fault at all. The object was alive
the whole time — objtrace shows `A(1) R(2) R(3) R(4) r(3) r(2) r(1)` and no free.
Its BLOCK was freed by someone who never owned it.

### The chain, measured end to end

`-dPXX_HEAP_DEBUG` reported WRITE AFTER FREE; a gdb hardware watchpoint on the
object's first word (its `Magic`) caught the writers in order:

1. `pyboundfn_new` writes Magic — legitimate.
2. `PXXAlloc + 0x167` — the FREE-BIN zeroing loop. The allocator handed the
   block out again, so it had been freed.
3. `PXXStrConcat` then builds a string in it, byte by byte.

Walking the stack past the release blob's 13 pushed registers named the freer:
**`PXXPromoClear`, called from `build_base_vm.w_repeat`**, on a stack slot
holding `{tag = 1, payload = <the live bound-fn object>}`.

`PXXPromoClear` releases the payload as a managed AnsiString whenever the tag
word reads `PROMO_TAG_HEAP` (1). Its own header says it must not be run on
uninitialised memory — "it tests the old tag and would release a garbage
payload" — and that is exactly what happened: `w_repeat` returns early, its
promo local at that depth was never written, and the frame garbage under it
read as a heap-tier slot pointing at a live object.

### Root cause: cleanup without init

`EmitManagedLocalCleanup` clears EVERY promo local at scope exit. Its
counterpart `EmitManagedLocalsZeroInit` — the one owner of the zero-init
contract, listing dynamic arrays, AnsiStrings, variants, managed records, COM
interfaces and NilPy class locals — **had no promo arm**. Promo TEMPS were safe
only because `IRPromoTempSlot` flags them `SymIsHiddenArgTemp`, which buys a
prologue zero; named promo LOCALS got nothing.

One line, in the list where the other half of the contract already lives:
`TypeIsPromoInt` -> zero `TypeSize` bytes, so the tag starts `PROMO_TAG_INLINE`.

### Why it presented as a callable bug

Undefined behaviour again. The freed block is only fatal once the allocator
REISSUES it, so BEGIN, WHILE, IF and THEN dispatched fine and REPEAT did not,
with nothing distinguishing them in uforth's source. The visible failure was
`pyvar_callv1` finding neither closure nor bound-fn magic and jumping into
string data — three layers and thousands of lines from a promo local in an
unrelated function.

### Verified

`test/test_nilpy_promo_local_zero_init.npy` (new). It DISCRIMINATES, and was
A/B'd against MY OWN change rather than against `pinned`: rebuilding HEAD with
`and False` on the new branch segfaults, with it the output matches CPython.

`make compiler/pascal26` byte-identical · `tools/gate.sh quick` GREEN.

## Also fixed here: `select.select` was a stub

Once the crash was gone, uforth ran but printed a `UF> ` prompt on every piped
line where CPython prints none. `pyselect_select` returned three EMPTY lists
unconditionally — not a degraded answer but the wrong one, since uforth
suppresses its prompt with
`if sys.stdin in select.select([sys.stdin], [], [], 0)[0]`.

Implemented for real: new `PyPalPoll` in `pypal.pas` (ppoll(2) — aarch64 and
riscv32 have no plain poll, ppoll exists on all five targets, one number each),
and `pyselect_select` now polls each entry and returns the ready subset. A NilPy
`sys.stdin` IS its file descriptor (the integer 0), so an entry polls as itself
and comes back as the same value — which is what makes the `in` test agree with
CPython. None timeout blocks; a float timeout is seconds, as CPython spells it.

`test/test_nilpy_select_stdin_ready.npy` covers it.

## make test-uforth: PASS

uforth compiles, boots, loads `STD.UFO`, and both smoke words evaluate
(`1 2 + . = 3`, `10 3 / . = 3`). [[bug-nilpy-uforth-compiles-but-segfaults-at-runtime]]
is GREEN and closed.

Deeper uforth corpora are NOT green yet — `tests/*.for` hit a separate
`<lambda>() takes 0 positional arguments but 1 were given` in pyeval on `value`
/ `TO` / `create` / `allot`. Filed separately; it is beyond this ticket's gate.

## Log
- 2026-08-08 — resolved, commit 7090e6818.
