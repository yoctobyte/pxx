---
track: N
prio: 35
type: bug
summary: "`rd().field` does not PARSE when rd() returns a module global that was pre-created because a def above reads it — 'unexpected token'. Binding the call result to a name first works, so only the direct selector-off-call-result form fails"
---

# A def returning a pre-created global has no usable return type

```python
class K:
    def __init__(self):
        self.z = 7

def rd():
    return g            # g is pre-created by PyAllocModuleGlobals

g = K()
print(rd().z)           # pascal26: error: unexpected token   near: rd >>> z
```

CPython prints 7. Binding first works:

```python
r = rd()
print(r.z)              # fine
```

So the value and its class are right; only `<call>.field` directly fails, and it
fails at PARSE time, not at run time.

## Pre-existing

Identical on `stable_linux_amd64/default/pinned`. Found while fixing
[[bug-nilpy-global-named-like-a-ctor-param-breaks-a-bound-method-value]], whose
test wanted `plain_reader().hits`; that test now binds to a name first and
names this ticket in a comment.

## Likely shape

`rd`'s return type is inferred by `PyInferDefRetType` from its body. The body is
`return g`, and `g` is a **pre-created** module global — the symbol exists when
the def is parsed, so the read resolves, but whatever the inference records is
not a class the selector path can use, so `.z` has nothing to bind against and
the parser reports an unexpected token rather than a typed error.

Note the fix to the parent ticket makes the pre-created symbol carry its class
(tyClass + RecName) when the pre-pass inferred one, so the information IS
present now — this may be a matter of `PyInferDefRetType` reading it. Worth
re-measuring before designing anything: the parent's fix landed after this was
observed, and the observation above was made on a build that already had it (it
failed identically on both, so the fix does not address it — but confirm).

## Gate

Per-fix loop, plus a `.npy` test covering `rd().field`, `rd().method()` and the
bind-first form, diffed against CPython.

## 2026-08-07 — narrowed: not ordering, and the fix hits a two-pass ABI constraint

The guess in "Likely shape" (that the parent's class-carrying fix might have
already supplied the information) is **wrong** — re-measured after that fix
landed and `rd().z` still fails. Two more measurements move it on:

| shape | result |
| --- | --- |
| `def rd(): return g` with `g = K()` **above** it | still fails |
| `def rd2(): return K()` (a fresh construction) | **works** |
| `r = rd(); r.z` (bind first) | works |

So it is **not** declaration order, and not the pre-created global's type: a
returned CONSTRUCTION types fine, a returned bare IDENT naming a module global
does not. And the value is genuinely a `K` at run time — only the call node's
STATIC type is missing, which is why binding to a local first works (the local
is typed by the trial parse).

### Where it stops

`PyInferDefRetType`'s bare-ident path (pyparser.inc ~18355) chases *"the ident's
ASSIGNMENT earlier **in the body**"*. A module-level global is assigned outside
the body, so there is nothing to chase, and `PyInferExprType` only resolves a
bare ident through `PyLocals`.

That is the constraint, and it is recorded in the code right there: **`PyLocals`
exists in the HEADER pass but not in the pre-pass**, and the comment warns that
trusting it in one and not the other made *"the two passes infer different
return types, a silent ABI mismatch."* So teaching only the header pass to
resolve module globals reintroduces exactly that hazard.

A correct fix has to make the global's type available to BOTH passes. The
natural home is the `repeat … until not changed` fixpoint in
`PyCollectModuleLocalsAST` — re-infer def return types inside it — but the
ordering is genuinely circular (typing a global assigned from a call needs the
def's return type; typing that return needs the global), which is why the loop
exists at all.

### Parked

Not a small fix, and the failure mode of getting it wrong is a silent ABI
mismatch rather than a loud error. The workaround (`r = rd()` then `r.z`) is
correct, cheap and already used in
`test/test_nilpy_global_read_above_its_assignment.npy` with a comment naming
this ticket.
