---
track: N
prio: 60
type: bug
summary: "`tuple(v)`, `sorted(v)`, `bytes(v)`, `reversed(v)`, `sum(v)` SEGFAULT when v is a variant holding a string — overload resolution binds a TPyList parameter and inserts an unchecked pyvarobj unwrap, so a string handle is reinterpreted as an object"
---

# A variant argument binds a CLASS overload and is unwrapped unchecked

```python
xs = ["cab"]
for x in xs:          # x is a VARIANT holding a string
    print(tuple(x))   # SIGSEGV
```

Five builtins crash on this shape. All of it is ordinary Python that CPython
runs (or rejects with a clean `TypeError`), and **a segfault is the worst
available outcome** — worse than any of the wrong answers beside it.

## Measured 2026-08-09 at HEAD; pre-existing on `pinned`

Receiver is a variant obtained the ordinary way (a list element):

| call | v holds a str | v holds a list |
| --- | --- | --- |
| `list(v)` | correct | correct |
| **`tuple(v)`** | **SIGSEGV** | correct |
| **`sorted(v)`** | **SIGSEGV** | correct |
| **`bytes(v)`** | **SIGSEGV** (CPython: TypeError) | correct |
| **`reversed(v)`** | **SIGSEGV** | wrong shape (returns a list; separate) |
| **`sum(v)`** | **SIGSEGV** (CPython: TypeError) | correct |
| `len`, `max`, `min`, `any`, `all`, `str`, `repr`, `abs` | correct | correct |

`list` is the tell: it is the only one of the crashing group that **has a
`Variant` overload** (`function list(const v: Variant): TPyList`, pylib.pas).

## Cause — located in the IR

`PXXDBG=a.ir` on `return list(x)` vs `return tuple(x)`, same program shape:

```
list:    call 574(lea x)                      -> tk=6   (tyClass)      ONE call
tuple:   call 683(lea x) -> tk=17 (tyPointer)
         call 610(that)  -> tk=6              TWO calls
```

`tk=17` is `tyPointer`: overload resolution picked `tuple(l: TPyList)` — the
only shape that could accept the argument once no `Variant` overload existed —
and inserted a **`pyvarobj` unwrap** to get there. `pyvarobj` hands back the
variant's raw payload. When the variant holds a **string**, that payload is an
AnsiString handle, and the callee immediately uses it as a `TPyList` instance
pointer.

So this is not five bugs in five builtins. It is **one hole in argument
lowering**: a `Variant` argument is allowed to bind a class parameter, and the
unwrap that makes it fit is unchecked. Any pylib builtin whose overload set
lacks a `Variant` row is on the wrong side of it, and every one added later
starts there by default.

## Two layers, and they are different fixes

1. **Safety, general.** The unwrap must be tag-checked: if the variant does not
   hold an object, raise the same `TypeError` a wrong argument type raises
   everywhere else. That converts the whole family — including builtins nobody
   has tested yet — from a segfault into a Python-shaped error, and it is the
   layer that keeps working as pylib grows. This is the one that matters.
2. **Correctness, per builtin.** `tuple(v)` and `sorted(v)` on a string variant
   should DO the Python thing, not raise — so they additionally want `Variant`
   overloads that dispatch on the tag, mirroring `list(const v: Variant)`.
   `bytes(v)`/`sum(v)` on a str are TypeErrors in CPython, so layer 1 alone is
   already correct for them.

Do layer 1 first and independently: it is the crash, it needs no per-name list,
and layer 2 is then a behaviour improvement on top of something that is already
safe.

## Located to the line

The unwrap is `compiler/ir.inc:2397`, in `IRLowerCallArg`:

```pascal
{ NilPy: a VARIANT argument to a CLASS-typed parameter unboxes via pyvarobj }
if PyProgramMode and ... and (IntToTypeKind(ASTTk[argAST]) = tyVariant) and
   (Procs[cpi].Params[pathIdx].TypeKind = tyClass) and ... then
begin
  caSlCall := FindProc('pyvarobj');
  ...
```

Guarded on `PyProgramMode`, so it is NilPy-only and Pascal cannot be affected by
changing it.

## Correction: `pyvarobj` itself must NOT be made to check

The obvious shortcut is to put the tag test inside `pyvarobj`. **That is wrong**,
and it is worth writing down before someone tries it: `pyvarobj` is also what the
runtime-dispatch arms call — `pyvarobj(v) is C ? <call as C> : ...` in
`PyParseVariantMethod` and the `isinstance` lowering. Those pass variants holding
strings and ints ON PURPOSE and need the test to simply come back False. Making
`pyvarobj` raise would turn every one of those dispatch chains into an exception
on its first non-matching arm.

So layer 1 needs its OWN entry point (`pyvarobj_arg` or similar) that raises
`TypeError` unless the tag is VT_OBJECT, with None still unwrapping to nil since
passing None to a class parameter is legitimate.

## Note on the gate — BOTH layers need a re-pin

Corrected: layer 1 is not frontend-only. It needs the new pylib routine above, so
like layer 2 it edits `compiler/builtin/**` and `gate.sh`'s self-host fixedpoint
will report A != B until `stabilize` + `pin`. Expected, not a regression — and
the sh-A/sh-B map diff is how to PROVE that rather than assume it
(`project_builtin_change_needs_repin_for_gate_fixedpoint`). Budget for the re-pin
when picking this up; it moves the ground every other track builds on, so it is
not a change to land in a hurry.

## Found by

Scoping [[bug-nilpy-lambda-returning-a-call-result-container-yields-none]]. That
ticket reported `lambda x: sorted(x)` as yielding None; it actually SEGFAULTS,
and varying the shape showed the lambda was irrelevant — a plain
`def g(x): return tuple(x)` crashes identically, and so does a bare
`print(tuple(x))` in a loop. The lambda fix landed separately and is real, but
it could never have fixed these: they were never a lambda problem.

## Gate

`.npy` diffed against CPython over the table above — every crashing row, both
payload kinds, plus the non-crashing builtins as controls so a fix that
tag-checks too eagerly is caught. `make test-nilpy` + self-host byte-identical.
