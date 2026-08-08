---
track: N
prio: 50
type: bug
summary: "SILENT->CRASH: a lifted CLOSURE stored into a `Callable` field lands as a VARIANT in a POINTER slot, so calling the field jumps to the tag word — PC = 0x0a, literally VT_BOUNDFN_TAG. This is what segfaults uforth now."
status: done
owner: claude-NA
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

## RESOLVED 2026-08-08 — three changes, all in `compiler/pyparser.inc`

The unification the ticket describes was right, and the "plain def assigned
after construction" gap it names was a MISREADING of the measurement: `dc3`
was not failing on the assignment at all. The narrowing that found it is worth
recording, because two of the three fixes were invisible from the reported
symptom.

Measured with a 16-cell matrix — {plain def, lifted closure, bound method,
lambda} x {@dataclass field, plain-class field} x {set via constructor, set by
later assignment}, one file per cell, each oracle-diffed with `tools/pydiff.py`
(now `test/test_nilpy_callable_field_all_shapes.npy`, 16 rows in one file):

| build | passing |
| --- | --- |
| HEAD before the change | 10/16 |
| + always-variant alone | 12/16 |
| + all three fixes | **16/16** |

### 1. `PyAnnTypeAt` — a `Callable` FIELD is a variant, like a PARAMETER

The `PyAnnParamScope` guard is gone: the branch always answers `tyVariant`.
That deletes the third representation. The signature is still RECORDED for a
field (`PyAnnLastProcSig` survives, only a parameter drops it) because
`UFldProcSig >= 0` is the MARKER the dynamic-receiver scan uses to recognise a
callable field — it is no longer an ABI, since the slot is a variant and
`parser.inc`'s `tyPointer/tyRecord + UFldProcSig >= 0` indirect-call
marshalling deliberately no longer fires.

### 2. `PyDcDefaultNode` PYDC_NIL — a variant field's `= None` is `pynone()`

**This, not the assignment, is what `dc3` was dying on.** Every dataclass field
default maps `None` to the ordinal `0`; a variant is 16 bytes passed by
ADDRESS, so once the field became a variant the constructor was handed a bare
`0` where it wanted a slot. `DC("x")` — merely OMITTING the callable argument —
segfaulted inside the constructor before its first statement, which is why all
four `assign`-column cells failed and only the `def` one had been noticed. Same
substitution `ir.inc`'s `ProcParamDefaultIsNone` branch already makes for a
variant PARAMETER's omitted default.

The reported "a plain def assigned into a variant field stores an unboxed
pointer" never happened: `d.native = plain` was fine all along, and no boxing
change was needed. `PyBoxCallableValue` / `PyNodeIsCallableValue` are untouched.

### 3. `PyMakeVariantFieldCall` — dispatch through `pyvar_callv<n>`

The dynamically-typed-receiver path (`def run(o): o.native(vm)`) hard-coded
`ASTTk[fieldNode] := tyPointer` and emitted a typed `AN_CALL_IND`. Reading a
variant slot as a bare code address is the tag-jump again, one layer out. It
now reads the field at its real `UFldTk` and, when that is a variant, calls the
universal dispatcher — the one thing that tells all four shapes apart. The
typed-indirect lowering stays for a genuinely pointer-typed procedural field.

### Boundary untouched, as decided

`pyvar_callable_ptr` was not modified. Variant inside NilPy, plain-def-only at
the FFI boundary.

## uforth: the tag-jump is GONE, the crash MOVED

Do not read this as fixed. Rebuilt at this change:

- **before:** `uforth.py:841` `word.native(self)`, **PC = 0x0a** (= VT_BOUNDFN_TAG).
- **now:** **PC = 0x4dfce7, inside `pyboundfn_callvn`** (`.map`-symbolised;
  `readelf` is blind on pxx binaries). A real code address — the tag-jump is
  gone.

The faulting instruction is the one AFTER the bridge's indirect call:

```
  mov %rax,%r10 ; pop %r11 ; call *%r11 ; push %rax
=> mov (%rax),%rcx        <-- rax = 0
```

`pyboundfn_callvn` invokes the body through `TBF<n>`, a **Variant-returning**
function type (`rv := f1(p[0])`), but uforth's native words are explicitly
`def w_plus(vm: VM) -> None:` — real PROCEDURES, which never set `rax`. So the
result is read from a null pointer. `TBoundFnObj` has no `IsFunc` field, unlike
the `pybound_new` path which carries exactly that flag for exactly this reason
(bug-nilpy-void-def-assigned-and-called-crashes) — that looks like the shape of
the next fix, but it is NOT confirmed: the obvious minimal repros of it
(`-> None` nested def in a dataclass field, direct and through a keyword
`define_word`) both PASS. Whatever uforth hits needs one more ingredient.

It now crashes during STARTUP, before the banner, so it is a native word run
while loading `STD.UFO` rather than line 841's token. Recorded on
[[bug-nilpy-uforth-compiles-but-segfaults-at-runtime]].

## Found alongside, filed separately (both PRE-EXISTING — confirmed by
## reproducing them under `stable_linux_amd64/default/pinned`)

- [[bug-nilpy-plain-class-callable-field-unreachable-through-a-dynamic-receiver]]
- [[bug-nilpy-dynamic-receiver-callable-field-casts-to-the-wrong-class]]

## Gate run

`make compiler/pascal26` (byte-identical fixedpoint, converged in 1 round) ·
`tools/gate.sh quick` GREEN (self-host fixedpoint 36s, testmgr --tier quick 7s,
FPC seed canary) · `test_nilpy_callable_field_call_returns` and
`test_nilpy_callable_param_heap_callable` both still green ·
`test_nilpy_callable_field_all_shapes` added to `make test-nilpy`.

## Log
- 2026-08-08 — resolved, commit PENDING-COMMIT.
