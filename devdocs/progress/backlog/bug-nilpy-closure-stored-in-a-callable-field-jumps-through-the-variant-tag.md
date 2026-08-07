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
