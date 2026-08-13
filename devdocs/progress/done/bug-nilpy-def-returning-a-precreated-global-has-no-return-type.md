---
track: N
prio: 35
type: bug
summary: "`rd().field` does not PARSE when rd() returns a module global that was pre-created because a def above reads it — 'unexpected token'. Binding the call result to a name first works, so only the direct selector-off-call-result form fails"
status: done
owner: claude-A-N
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

## 2026-08-09 — DIAGNOSED and parked (claude-AN). The "likely shape" above is wrong.

Attempted, measured, reverted. Nothing landed; what follows is the finding, so
the next session does not re-derive it.

### The boundary, mapped

| shape | result |
| --- | --- |
| `def rd(): return g` … `g = K()` after, `rd().z` | **error** |
| same but `g = K()` BEFORE the def | **error** (different message) |
| `r = rd(); r.z` | works |
| `def rd() -> K: return g` (annotated) | works |
| `def mk(): return K()`, `mk().z` | works |
| `def mk(): w = K(); return w`, `mk().z` | works |

So it is **not** the call-result selector path (`mk().z` is fine), and **not**
about the global being pre-created or about ordering — the annotated form proves
the selector path works the moment the return type is known. It is exactly:
*a bare-ident return naming a MODULE GLOBAL has no inferred type*.

### Why the obvious fix does not work — measured, not reasoned

The bare-ident chase in `PyInferDefRetType` (~19200) scans only the DEF BODY for
an assignment to that name and finds nothing for a global. The obvious extension
is to fall back to the module tables. Implemented, and it **never fired**. A
probe printed at that point:

```
PROBE ret bare=g cur=0 chain=0 constraint=-1 progsym=-1
```

`cur` and `chain` are `tyUnknown`, and **both `PyFindConstraint` and
`PyProgSym` answer −1**: at the moment a def's return type is decided, the
module global does not exist in either table yet. `PXXDBG=n.locals` reports
`g tk=6 rec=0` for that same program, so the information does exist — just
later. The probe printed **once**, so the header inference is a single decision
at def-parse time and is not revisited by the pre-pass fixpoint.

That makes this a PASS-ORDERING problem, not a missing lookup, which is why it
was parked rather than microfixed: the fallback compiles, looks like a fix, and
is dead code.

### The two honest routes

1. **Revisit the return type in a later round.** The module pre-pass is already
   a fixpoint over rounds (`PyTypingChanged`); a def whose return type came back
   `tyUnknown` from a bare ident could be re-inferred once module globals are
   typed, at which point the fallback above starts working unchanged. Check
   `PyHdrRetType := PyInferDefRetType(...)` at ~17998 and ~18015 — there are two
   call sites and one may already be a second chance.
2. **Type module globals before defs are parsed**, at least for the safe shapes
   (a constructor call of a declared class is one — the same recognition added
   for [[bug-nilpy-block-nested-scalar-then-class-rebind-loses-widening]]).

Route 1 looks smaller and cannot regress a def whose return type is already
known, since it would only re-ask when the answer was `tyUnknown`.

### Workaround, unchanged
Annotate the def (`-> K`) or bind the call result to a name first. Both are
verified working above, and the annotation is the documented escape hatch for
anything this pre-pass cannot resolve.

## FIXED — verified 2026-08-13, closing with the regression it lacked

`rd().z` parses and answers 7. Fixed by the return-type inference / selector
work since this was filed, not by anything done here; re-measured directly
rather than assumed, and swept past the one shape the ticket recorded: a field,
a method call, a subscript, a chain mixing two such calls, and the
bind-to-a-local control all match CPython.

`test/test_nilpy_selector_off_call_returning_a_global.{npy,expected}`
(`.expected` from CPython), wired into `test-nilpy` — the rows vary what
FOLLOWS the call, because each is a different selector arm and the original
failure was in the parse.

Gate: self-host fixedpoint + `gate.sh quick` GREEN.

## Log
- 2026-08-13 — resolved, commit PENDING-COMMIT.
