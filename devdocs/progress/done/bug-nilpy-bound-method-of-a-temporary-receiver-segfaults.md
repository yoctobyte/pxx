---
track: N
prio: 45
type: bug
summary: "`f(C().m)` — a bound method whose receiver is a TEMPORARY — segfaults. `c = C(); f(c.m)` is fine, so the pair outlives the instance it points at: a receiver-lifetime bug, not a callable-value one"
status: done
owner: claude-AN
---

# A bound method of a temporary receiver segfaults

```python
class C:
    def m(self, x):
        return x + 100

def ap(f, v):
    return f(v)

print(ap(C().m, 5))          # CPython: 105    pxx: SIGSEGV
```

Binding the instance to a name first is enough to make it work:

```python
c = C()
print(ap(c.m, 5))            # 105, correct
```

## Measured 2026-08-07 — pre-existing, and NOT about annotations

Found while fixing
[[bug-nilpy-bound-method-cannot-pass-through-a-callable-parameter]] and
deliberately kept out of that change's test, because attributing it there would
have blamed a pre-existing crash on a new commit.

| binary | `ap(C().m, 5)` — UNANNOTATED parameter |
| --- | --- |
| `stable_linux_amd64/default/pinned` (pre-change) | **SIGSEGV** |
| that session's HEAD | **SIGSEGV** |
| CPython | 105 |

Both ends crash, and the parameter carries no `Callable[...]` annotation, so
neither the annotation ABI nor the variant-typing change is involved. Every
other bound-method shape works: `c.m` assigned to a name, stored in a list,
passed through an unannotated parameter, and (since that fix) passed through an
annotated one, including two instances keeping their own receivers.

The single variable is whether the receiver is a **temporary**.

## Likely shape

`obj.method` in a value position builds a `{code, receiver}` pair
(`pybound_new`, pylib). When the receiver is a named local, that local holds a
reference and outlives the call. When it is `C()`, the instance is a call-result
temporary whose reference is dropped at the end of the statement — the pair then
points at a freed block, and the method runs with a dangling Self.

So the pair almost certainly does **not retain its receiver**. Check
`pybound_new` for a `PXXObjRetain` on the receiver half and
`PyObjFinalize`'s `rawKind <> 0` branch for the matching release — that branch
already releases both `Code` and `Recv`, which suggests the *release* side
exists and only the retain is missing. If so this is a one-line fix plus a test,
but confirm with `-dPXX_OBJTRACE`/`-dPXX_HEAP_DEBUG` before changing it: an
unbalanced retain would leak every bound method instead, and this family has a
history of confidently-wrong refcount fixes
([[bug-nilpy-bound-fn-closure-objects-are-never-freed]]).

## Gate

Per-fix loop, plus `test/test_nilpy_callable_param_heap_callable.npy` gaining
the `C().m` row that is commented out there today (the comment names this
ticket), byte-identical to the CPython oracle. Check `-dPXX_HEAP_DEBUG` is clean
on the repro, so the fix is not merely making the freed block survive by luck.

## FIXED 2026-08-07 — and the ticket's own guess was wrong

This ticket guessed the pair "almost certainly does not retain its receiver".
**It does** — `pybound_new` (pylib.pas) calls `PXXObjRetain(recv)` and has since
the object-reclamation work. Checked first, which is what stopped a one-line
"fix" to a routine that was already correct.

The real cause is the split this repo keeps finding: **`obj.method` as a VALUE
was built at exactly one site**, `parser.inc:6098` inside `ParseLValueAST` —
the BARE-IDENTIFIER path. Every receiver that reaches `ParseClassRecordSelectors`
instead (a constructor result, a function result, a method-chain result) fell
through to the CALL path and produced a bare code address with no receiver,
which segfaulted when called.

`-dPXX_OBJTRACE` is what showed it, in one line: the working `c.m` allocates
**two** blocks (the instance and the pair), the crashing `C().m` allocates
**one**. `pybound_new` was never reached, so there was nothing to look at on the
retain side.

The fix mirrors the `ParseLValueAST` arm into the selector path, guarded the
same way (`NilPyUserCode`, no following `(`, a known class, not an interface),
peeking `Tokens[TokPos]` because the method name is still current there. A
temporary receiver then survives precisely because the pair retains it.

This is the SECOND missing arm found in `ParseClassRecordSelectors` today — the
first was the class-attribute read through a non-bare receiver. Same routine,
same shape, same cause: two paths for one construct and only one of them
maintained. `devdocs/dev/normalise-dont-special-case.md`.

### Measured, controlled against PINNED

| receiver shape | pinned | fixed | CPython |
| --- | --- | --- | --- |
| `C(100).m` constructor result | **SIGSEGV** | 105 | 105 |
| `mk(200).m` function result | SIGSEGV | 205 | 205 |
| `C(300).me().m` method-chain result | SIGSEGV | 305 | 305 |
| `c.m` bare identifier | 405 | 405 | 405 |
| direct calls `C(500).m(5)`, `c.m(6)` | ok | 505 406 | 505 406 |

Test `test/test_nilpy_bound_method_value_receiver_shapes.npy`, 8 lines
byte-identical to the CPython oracle, including two pairs over two instances
keeping their own receivers and a temporary's pair stored and called later.

### Unchanged and NOT claimed: a receiver whose class is a run-time fact

`objs[0].m` and `box.inner.m` (a list element, a field typed from an untyped
parameter) raise `AttributeError` — **identically on the pinned binary**, so not
touched by this change. Those need the receiver's runtime class, the same
missing capability as the variant-receiver rows in the class-attribute family.
Loud, not silently wrong.

### A third bug found on the way, filed not folded

The first draft of the test used `a` and `b` as instance names and failed — on
the pinned binary too. A global named like another class's ctor parameter breaks
a bound-method value:
[[bug-nilpy-global-named-like-a-ctor-param-breaks-a-bound-method-value]], filed
with the four-row narrowing showing each ingredient alone is insufficient. The
test now uses non-colliding names, because a test whose variables collide
reports somebody else's bug — the lesson already recorded in
[[project_nilpy_name_matching_a_class_is_typed_as_that_class]].

### Gate

`make fpc-check` byte-identical, self-host fixedpoint, `tools/gate.sh quick`.

## Log
- 2026-08-07 — resolved, commit 99c32f284.
