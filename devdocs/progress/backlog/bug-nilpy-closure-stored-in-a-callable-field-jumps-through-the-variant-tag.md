---
track: N
prio: 50
type: bug
summary: "SILENT->CRASH: a lifted CLOSURE stored into a `Callable` field lands as a VARIANT in a POINTER slot, so calling the field jumps to the tag word — PC = 0x0a, literally VT_BOUNDFN_TAG. This is what segfaults uforth now."
---

# A closure in a Callable field jumps through the variant tag

21-line repro:

```python
@dataclass
class Word:
    name: str
    native: Optional[Callable[["VM"], None]] = None

def make_word(name, k):
    def _w(vm):                 # a lifted CLOSURE (captures k)
        vm.n = vm.n + k
    return Word(name, _w)

w = make_word("INC", 5)
w.native(vm)                    # SIGSEGV, PC = 0x0a
print(vm.n)                     # CPython: 5
```

`PC = 0x0a` is the diagnosis: **10 is `VT_BOUNDFN_TAG`**. A `Callable` FIELD is
typed `tyPointer`, a lifted closure is a VARIANT, so the store puts the
variant's TAG WORD in the slot and the call jumps to address 10.

A plain `def` in the same field works, because that value really is a bare code
address.

## This is uforth's current segfault

`uforth.py:841`, `word.native(self)` on token `INCLUDE`, PC = 0x0a. uforth's
`define_word` returns exactly this shape — a `Word` dataclass whose `native` is
a nested def. Blocks [[bug-nilpy-uforth-compiles-but-segfaults-at-runtime]].

## The fix is a UNIFICATION, and it is half-measured already

There are now three representations for one concept: a `Callable` PARAMETER is a
variant (since [[bug-nilpy-bound-method-cannot-pass-through-a-callable-parameter]]),
a field typed FROM such a parameter follows it
([[bug-nilpy-callable-field-typed-only-by-a-ctor-parameter-has-no-signature]]),
and a field declared directly is still a pointer. That third one is this bug.

**Making every `Callable` a variant was tried and MEASURED**, by deleting the
`PyAnnParamScope` condition in `PyAnnTypeAt`'s callable branch so it always
answers `tyVariant`:

| repro | always-variant |
| --- | --- |
| `clos` — closure in a dataclass field (THIS bug, and uforth's) | **fixed** |
| `dc`, `dc2`, `dc4` — dataclass Callable fields | pass |
| `fc2`, `fc3`, `fld`, `fld2` — plain-class Callable fields | pass |
| `mat` — bound method through a Callable parameter, all 6 rows | pass |
| **`dc3` — a PLAIN DEF assigned to the field after construction** | **BREAKS** |

So the unification is right and one gap stands in the way: assigning a plain
`def` (a bare code address, no tag) into a now-variant field stores an unboxed
pointer, and the dynamic call then misreads it. It needs boxing at the
field-assignment site — `pyvar_of_callable` is the boxer and `PyDefUsedAsValue`
is the existing "a def used as a value" hook; the question is why that hook does
not fire for a FIELD target when it does for a local.

Reverted rather than shipped half-done: fixing a closure crash by introducing a
plain-def crash is not a trade.

## Gate

Per-fix loop, plus a `.npy` covering all four combinations — {plain def, lifted
closure, bound method, lambda} x {dataclass field, plain-class field}, set both
through the constructor and by later assignment, oracle-diffed. And
`make test-uforth` getting past `uforth.py:841`.

## DECIDED 2026-08-08 (user): the FFI boundary takes PLAIN FUNCTIONS ONLY

Asked whether `Callable[...]` should mean "any Python callable" (variant,
closures allowed, needing a trampoline to reach C) or "a C-compatible function
pointer". Answer:

> not 'any python callable'. we can assume externally called functions do have
> limitations. as any proper library would — we don't need voodoo code where
> pascal calls python lambda's via a function variable or so.

So there are **two regimes and one conversion point**, and no trampoline
machinery is wanted:

- **INSIDE NilPy** a `Callable` value is a variant and may be any of the four
  shapes — plain def, pyeval closure, lifted bound-fn, bound method. This is
  what lets a closure live in a field at all, and it is the half this bug is
  about.
- **CROSSING to Pascal/C** as a raw function pointer, only a **plain def**
  qualifies — its value genuinely IS a code address. A closure or a bound method
  carries state that does not fit in 8 bytes and is **refused, loudly**. That is
  a library limitation, not a defect, exactly as any FFI has.

`pyvar_callable_ptr` (pylib) already implements precisely this and its
diagnostic already says so, so **the boundary needs no change** — it was right
before this ticket and stays right. The tkinter registry/trampoline pattern is
NOT to be generalised; it is Tk's own business.

### Consequence for the fix

Only the internal half is in scope:

1. Unify the internal representation — a `Callable` PARAMETER and a `Callable`
   FIELD are both variants, removing the third representation that causes this
   crash.
2. Close the one gap the measured experiment exposed: a **plain def** assigned
   into a now-variant field must be BOXED (`pyvar_of_callable`) instead of
   stored as a bare code address.
3. Leave `pyvar_callable_ptr` alone.

Nothing here needs a Track U ticket any more — the fork above was the only open
question and it is answered.
