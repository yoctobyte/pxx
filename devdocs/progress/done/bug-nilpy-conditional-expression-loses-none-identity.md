---
track: N
prio: 50
type: bug
summary: "SILENT: `w = f() if c else None` where f() returns None makes `w is None` answer FALSE — boxing a NIL class pointer into a variant tags it VT_OBJECT instead of VT_EMPTY, so a None guard is entered and the next line dereferences null. This is what segfaults uforth."
status: done
owner: claude-AN
---

# A conditional expression loses None identity

```python
class Word: ...
class VM:
    def lookup_word(self, name: Any) -> Optional[Word]:
        ...
        return None                      # not found

vm = VM()
k = "MISSING"
w = vm.lookup_word(k) if isinstance(k, str) else None
print(w is None)                         # CPython True    pxx FALSE
if w is not None:
    w.is_native()                        # entered, then SIGSEGV
```

**Silent wrong value first, crash second** — `is None` answering False on a
value that IS None is the bug; the segfault is only how you notice.

The SAME assignment without the conditional expression is correct:

```python
w = vm.lookup_word(k)
print(w is None)                         # True — correct
```

One construct, two spellings, different answers.

## Root cause — located, not guessed

`PXXDBG=n.locals` on the two spellings:

| spelling | recorded |
| --- | --- |
| direct | `w tk=6 rec=0` — tyClass |
| conditional expression | `w tk=22 rec=0` — tyVariant |

So the ternary widens the result to a VARIANT, which means the class pointer
gets BOXED. The boxing site is `ir_codegen.inc` ~5580:

```pascal
  tyClass:  size := VT_OBJECT;
  ...
  EmitB($48); EmitB($C7); EmitB($07); EmitI32(size);  { mov qword [rdi], tag }
  EmitB($48); EmitB($89); EmitB($4F); EmitB($08);     { mov [rdi+8], rcx }
```

The tag is stored **unconditionally**. A nil class pointer therefore boxes as
`VT_OBJECT` with payload 0 — a variant that is not VT_EMPTY, so every
`is None` / truthiness test on it answers the opposite of Python.

## Fix

For `tyClass` only, the tag must depend on the payload: nil → `VT_EMPTY`
(Python's None), non-nil → `VT_OBJECT`. In the emitted blob, `rdi` holds the
slot address and `rcx` the payload at that point, so it is a store, a `test
rcx, rcx`, and a conditional overwrite of the tag with 0 — a manually patched
forward jump, as several blobs in that file already do (see
`EmitDynArrayReleaseLocked` for the idiom and why the jumps are patched by hand).

Mirror it in the portable twin if that path boxes classes too, and check the
other five backends — this is emitted code, so a fix in the x86-64 blob alone
would leave the cross targets disagreeing.

## Why it matters

**This is what segfaults uforth** ([[bug-nilpy-uforth-compiles-but-segfaults-at-runtime]]).
`uforth.py:838-841` is exactly this shape:

```python
word = self.lookup_word(key) if isinstance(key, str) else None
if word is not None:
    if word.is_native():        # <-- rdi = 0, `mov (%rdi),%rax`
```

Registers at the fault confirm it: `rax=0 rdi=0`.

More generally `x = f() if cond else None` is ordinary Python, and every None
guard after one is currently unreliable when f() can return None.

## Also noticed, not fixed

The pre-pass records the conditional-expression local as `tk=tyVariant rec=0` —
a variant carrying a class identity, which is contradictory (the field path
normalises this with `if tk <> tyClass then fldRec := REC_NONE`). Clearing it in
`PyNoteLocalType` was tried, changed the record to `rec=-1`, and did **not** fix
this bug, so it was reverted rather than shipped unmeasured. Worth revisiting as
a separate normalisation — a sticky `PyInferLastCi` leaking into a non-class
type could well be behind other symptoms.

## Gate

Per-fix loop, plus a `.npy` covering: a conditional expression whose taken arm
returns None, whose taken arm returns a real object, the `else None` arm, the
direct (non-conditional) assignment, and the same through a variable of
`Optional[X]` type — oracle-diffed. And `make test-uforth` getting past
`uforth.py:840`.

## FIXED 2026-08-07

A nil class pointer now boxes as `VT_EMPTY` — which is what Python's None IS —
instead of `VT_OBJECT` with a 0 payload. Both boxing sites in `ir_codegen.inc`
take the same three instructions after the tag store:

```
test rcx, rcx
jne  +7
mov  qword [rdi], VT_EMPTY
```

The skipped store is exactly 7 bytes, so the jump is a fixed short one and needs
no manual patching — unlike the blobs elsewhere in that file.

Both sites, not one: the same sequence appears in the variant-assignment path
and the variant-operand-temp path, and fixing only the first would have left the
other spelling wrong, which is the split this codebase keeps finding.

### Measured

`test/test_nilpy_conditional_expression_none.npy`, 9 lines byte-identical to the
CPython oracle: the conditional expression whose taken arm returns None, whose
taken arm returns a real object, the `else` arm, the direct assignment that was
always correct (kept as a guard against "fixing" the ternary by breaking it),
truthiness of the boxed None, and a None-returning call through a plain
variable. The whole Callable-field and Optional-method family from earlier the
same day still passes.

### uforth: the fault MOVED, which is the point

Before: `uforth.py:840`, `mov (%rdi),%rax` with **rdi = 0**, on token
`"CORE.UFO"` — the null deref this bug caused.

After: `uforth.py:841` (`word.native(self)`), on token **`INCLUDE`**, with
**PC = 0x0a** — a jump through a garbage code pointer. A different failure, one
line later, on a token that only gets reached now that the None guard behaves.

So uforth is not fixed, but this was genuinely on its path. The next failure is
a Callable FIELD call through a variant receiver where the field was bound via
`define_word(name, native=_w)` — a KEYWORD argument through the pyeval
fallback, i.e. the shape
[[bug-nilpy-pyeval-fallback-still-binds-host-kwargs-by-position]] describes.
Recorded on [[bug-nilpy-uforth-compiles-but-segfaults-at-runtime]].

### Not shipped

Clearing the contradictory `tk=tyVariant rec=<class>` the pre-pass records for
such a local was tried, measured to change the record but NOT to fix this bug,
and reverted. Still worth doing as a separate normalisation — a sticky
`PyInferLastCi` leaking into a non-class type is the kind of thing that produces
another symptom elsewhere.

### Gate

`make fpc-check` byte-identical, self-host fixedpoint, `tools/gate.sh quick`
GREEN.

## Log
- 2026-08-07 — resolved, commit bd6edb9f0.
