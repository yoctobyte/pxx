---
track: N
prio: 55
type: bug
---

# NilPy: a `-> None` def assigned to a name, then called directly, segfaults

Found by accident while researching
[[bug-nilpy-callable-value-abi-sorted-key-and-builtins]] (confirmed present
against `stable_linux_amd64/default/pinned` from before that session's
changes, and still present after all of it landed — unrelated to that
ticket's fix).

## Repro

```python
def hit(vm) -> None:
    print("native ran")

f = hit
f(1)
print("done")
```

```
native ran
Segmentation fault (core dumped)
```

CPython prints `native ran` then `done`. pxx crashes right after `hit`'s own
body finishes running — `print("done")` never runs.

## Narrowed since first filed: it's specifically the EXPLICIT `-> None` shape

An UNANNOTATED void def (`def hit(vm): print(...)`, no `-> None` at all)
does NOT crash captured the same way — confirmed. NilPy defaults an
unannotated def with no value-returning `return` to being treated as a
FUNCTION (not a Pascal procedure) with an inferred placeholder return type,
and `PyDefUsedAsValue`'s existing forcing (`PyParseDefHeader`, pyparser.inc)
already promotes THAT case to a real Variant-returning function. Only a def
with an EXPLICIT `-> None` annotation registers as `Procs[pi].IsFunc = False`
— a genuine Pascal PROCEDURE, deliberately left alone by that same forcing
code (its own comment: "A procedure stays a procedure — there is no result
to disagree about").

## Why the field-storage shape (`w.native = hit`) does NOT crash

Measured precisely this session, not assumed: `test_nilpy_unpack_callable.npy`
uses the EXACT same `def hit(vm: Any) -> None:` shape, stored into a
`Callable[["VM"], None]`-typed dataclass field, called via `word.native(self)`
— and it works. The two call sites are NOT the same underlying mechanism:

- **Field call** (`word.native(x)`, parser.inc ~line 5985): lowers to
  `AN_CALL_IND` using `fldSigPi` — the FIELD'S OWN DECLARED SIGNATURE proc
  (registered from the `Callable[[VM], None]` annotation itself). That
  signature genuinely IS a void procedure type, matching `hit`'s real
  compiled ABI exactly, so the call is correct by construction. A closure/
  bound-fn possibility is layered on top via `PyWrapClosureFieldCall`
  (checking `pyclosure_is`/`pyboundfn_is`), but a Shape-A value (what
  `hit` becomes) falls through to that base `AN_CALL_IND`, which was
  ALREADY right for it.
- **Bare-name call** (`f(1)` on a plain Variant-typed local, no type
  annotation anywhere): goes through the GENERIC dynamic-call bridge
  (`pyvar_callv1`/`pybound_callv1` — see
  [[bug-nilpy-callable-value-abi-sorted-key-and-builtins]]'s research),
  which has no field/parameter signature to consult and so UNCONDITIONALLY
  casts the callee through `TPyCbF1 = function(const a0: Variant): Variant`
  — the Variant-hidden-destination-pointer convention `hit`'s real compiled
  procedure body never sets up.

## A fix was ATTEMPTED and REVERTED this session — record why

First attempt: force `Procs[hit].IsFunc := True` (making the def itself
always compile as a Variant-returning function, like the unannotated case
already does) whenever `PyDefUsedAsValue` is true, removing the "a procedure
stays a procedure" exception entirely.

This DOES fix the bare-name crash. It also BREAKS the field-call case:
`test_nilpy_unpack_callable.npy` regressed (segfault) — because
`fldSigPi` (the field's OWN declared signature, still a void procedure type
since the ANNOTATION never changes) now calls a `hit` that compiles with a
DIFFERENT real ABI (Variant-returning) than the signature it's being called
through expects. The mismatch just moved from one caller to the other.

**The actual gap: the SAME capture site (`PyMakeFuncValue`, and the
tkIdent-value-position handler in ParseFactorCore) feeds BOTH consumers**,
and there is no way to tell, at the point a bare def name is captured,
whether it is about to be assigned to a plain variable (needs the
Variant-returning ABI) or into a typed `Callable[...]` field (needs to stay
whatever its real ABI already is, matched by the field's own signature).
Forcing the def's OWN compiled signature is a global change; only ONE of
the two consumers can be right at a time.

## Shape of the real fix

The generic dynamic-call bridge (`pybound_callv0..3`/`pycallback_call0/1`,
pylib.pas) needs a RUNTIME way to know whether the `{code, recv}` pair it is
about to call is a genuine procedure or a function — nothing in
`TPyBoundRec` carries this today. Sketch:

1. Add a field to `TPyBoundRec` (pylib.pas) recording whether `Code` is a
   function or a procedure — set by `pybound_new` at the point of capture,
   which needs a new parameter for it.
2. Both `pybound_new` call sites (`PyMakeBoundMethod` and `PyMakeFuncValue`,
   pyparser.inc) already know `Procs[pi].IsFunc` at that point — thread it
   through.
3. `pybound_callv0..3` (and the `pycallback_call0/1` discard-result
   siblings) branch on the new field: a function callee keeps the current
   `TPyCbF1`-style Variant-returning cast; a procedure callee casts through
   a genuine `procedure(...)` type instead and sets `Result := pynone`
   directly, never reading anything back.

This is a real ABI extension across a shared, already-delicate subsystem
(the same one `bug-nilpy-callable-value-abi-sorted-key-and-builtins` and
`bug-nilpy-bound-fn-closure-objects-are-never-freed` both live in) — sizing
it as a dedicated pass, not a quick patch, is why this was reverted rather
than shipped half-tested this session.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` matching the
repro above AND `test_nilpy_unpack_callable.npy` (the field-call shape) both
passing, diffed against CPython.
