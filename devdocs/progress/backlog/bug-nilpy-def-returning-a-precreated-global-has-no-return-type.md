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
