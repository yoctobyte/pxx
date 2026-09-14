---
slug: bug-n-a-class-reference-receiver-walks-rtti-off-a-non-instance
title: a class-reference receiver walks RTTI off a non-instance and segfaults
summary: >
  `cls.SPAN` inside a @classmethod segfaults when a second class declares the
  same attribute name. The candidate arms test `pyvarobj(v) is C` to pick one,
  pyvarobj hands back the RAW payload whatever the tag is, and AN_IS_TEST
  lowers to __pxxInheritsFrom over `[[payload+0]-8]` -- so on a PyBoxClassRef'd
  receiver, whose payload is the class BLOB rather than an instance, the walk
  dereferences whatever lies 8 bytes before a word of RTTI. Five of the seven
  sites emitting that test carried no tag guard; they now share one that does.
  FIXED.
track: N
type: bug
prio: 90
owner: frank-user
status: done
---

## Reduction

`test/test_nilpy_dynamic_dispatch_on_a_classref_receiver_does_not_walk_rtti.npy`,
wired into `test-nilpy`. Two classes declare `SPAN` and `reach`; the classref
rows go last, because the instance arrangement passes either way.

Without the guard the fixture dies with rc=139 on the FIRST classref row,
having printed the two instance rows correctly. With it, all four rows match
CPython byte for byte.

## How it presented

lekkerzeilen's world path. Under `MALLOC_PERTURB_` it looked like one thing and
under valgrind like another; valgrind is what resolved it:

```
Invalid read of size 8 -- address 0x40000008, not stack'd, malloc'd or freed
  __pxxInheritsFrom + 0x114     <-- mov (%rax),%rax, rax = cur + 8
  App._bucket       + 0x9b2
  App._prepare
  App._loader
  PyBoundPairCallKwBody -> pybound_pair_call_kw -> pybound_pair_call
  PyBoundCallV -> pybound_callv0
  ThreadLauncher -> PalThreadCreate
```

`App._bucket` is a `@classmethod` whose first statement is `size =
cls.FOLIAGE_CHUNK`. Its source contains no `is`, no `isinstance` and no
`__class__` -- the RTTI walk is entirely compiler-generated, which is why
reading the Python did not point at it.

Disassembled, the site is unambiguous:

```
call PyBoxClassRef        ; cls -> a variant, payload = the class BLOB
...                       ; 16-byte copy into a hidden temp
call pyvarobj             ; -> the RAW payload.  NO pyvartag before it.
mov  (%rax),%rax          ; [blob+0]
sub  $0x8,%rax ; mov (%rax),%rax   ; [[blob+0]-8] -- "the RTTI blob"
call __pxxInheritsFrom    ; walks ->parent at +8.  0x40000000 + 8. SIGSEGV.
```

`ir.inc` documents that lowering: `blob = [[inst+0]-8]`, reflexive, the same
machinery `x.InheritsFrom(C)` uses. It is correct for an INSTANCE and is
nonsense for anything else.

## The fix

`PyMakeVariantIsTest(baseNode, ci)` in `pyparser.inc` -- one spelling of
`(pyvartag(v) = VT_OBJECT) and (pyvarobj(v) is C)`. Five call sites folded onto
it (two attribute arms, one field-call arm, the dual-candidate method arm, and
the dynamic-defaults fallback arm added at `accb99f3c`). Boolean `and` lowers
with `JUMP_IF_FALSE` over the right operand, so a non-object tag never reaches
the walk.

The guard was NOT new information. `pyparser.inc` already said, in its own
words, *"The tag guard on the object arm is not optional: pyvarobj hands back
the raw payload"* -- and the two sites that carried it were the two that had
been written next to that sentence. **Seven copies of ten lines, two of them
right.** That is the case for a function rather than a ninth copy, and it is
the `normalise-dont-special-case.md` failure in its usual shape: the second
path is the one that stays broken.

## Measured: `accb99f3c` did NOT cause this

That control was open in
`bug-n-a-callable-value-called-with-four-arguments-dereferences-a-variant-at-address-1`
and is now closed, two ways:

- Compiler rebuilt at `accb99f3c^` (55cdf94233a9), lekkerzeilen rebuilt from
  the same sources, run under valgrind: **the same fault, same frame, same
  offset** -- `App._bucket+0x9b2 -> __pxxInheritsFrom+0x114`, 228 errors from 5
  contexts against 218 from 4.
- Disassembled, both binaries carry the IDENTICAL call sequence in `_bucket`:
  `PXXVarClear, PyBoxClassRef, pyvarobj, __pxxInheritsFrom`, one call each. The
  fallback arm added by `accb99f3c` did not fire at that site and did not
  displace anything.

The suspicion was reasonable -- `accb99f3c` grew the RTTI param block and its
new arm emits `AN_IS_TEST` -- and it was wrong. Recorded because the cheap
reading was "the new commit touched RTTI, the crash is in RTTI".

## What this does NOT fix

The `rax=1` fault in `pybound_pair_call_kw` at arity 4, reached through
`App._draw_scene`, stays in its own ticket. Different thread, different arity,
different frame; it is a bad ADDRESS rather than a bad CLASS pointer.

`cls.some_static_method(...)` is separately broken and unrelated to the walk:
it answers `AttributeError: 'type' object has no attribute '<name>'` for a
staticmethod the class plainly declares. Filed separately.

## Gate

`make compiler/pascal26` (converged, b46c98d433f1), the fixture above with its
positive control, `make test-nilpy`.

## Log
- 2026-09-14 -- found hunting lekkerzeilen's world-path fault under valgrind
  after the owner installed it; fixed the same evening.
