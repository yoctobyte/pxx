---
track: N
prio: 40
type: bug
blocked-by: []
summary: "`self.k = G` where G is a module global holding an instance: typing the field from the global (either tyClass or tyVariant) compiles and then reads GARBAGE — 5887615 / 7 where CPython says 9. Today it is still the loud 'cannot infer' diagnostic, because typing it was measured and rejected; the value path is what has to be fixed before the inference can be extended"
status: done
owner: agent-AN
---

# A field assigned from a class-instance global reads garbage when typed

- **Type:** bug (latent silent wrong value) — **Track N**
- **Found:** 2026-08-12, while fixing
  [[bug-nilpy-a-field-assigned-from-a-module-global-has-no-inferable-type]].
- **Not user-visible today**: the shape below still produces the loud
  "cannot infer the type of field" diagnostic. This ticket is the reason it
  still does.

```python
class K:
    def __init__(self):
        self.z = 9

G = K()

class C:
    def __init__(self):
        self.k = G          # today: "cannot infer the type of field self.k"

print(C().k.z)              # CPython: 9
```

## Measured — both typings are wrong, and wrong differently

The sibling fix added `PyPreTypeModuleGlobals`, which types module globals from
their token shape before the class-field pre-pass runs. Extending it to the
constructor-call shape (`G = K()`) is a four-line, no-parse recognition — the
same one the depth>0 arm of `PyCollectModuleLocalsAST` already uses — and it
makes the program COMPILE. It then prints:

| field typed as | `C().k.z` prints | CPython |
| --- | --- | --- |
| `tyClass` + K's rec | **5887615** | 9 |
| `tyVariant` | **7** | 9 |

Two different plausible integers, neither of them the field. So the inference is
not the missing piece: whatever `self.k = G` stores is not the instance handle,
and the read is off in both the static-class and the variant lowering. The
recognition was therefore **removed again** rather than shipped — a loud
diagnostic beats a number that looks like an answer.

The removal is recorded in `PyPreTypeModuleGlobals` itself (pyparser.inc) with
both measurements, so the next person who notices the easy extension finds out
why it is not there before spending the session.

## Where to start

The store, not the inference. At the point `self.k = G` is lowered, `G` is a
module global pre-created by `PyAllocModuleGlobals` — the same pre-creation that
sits under [[bug-nilpy-def-returning-a-precreated-global-has-no-return-type]] —
so the first question is what the field write actually reads for `G` at that
moment (`PXXDBG=n.locals` for the global's own type, then the IR for the store:
`PXXDBG=a.ir:__init__`). A local bound to the same instance (`k = G` then
`k.z`) works, which is the control worth running first: it isolates the FIELD
store from the global read.

## Gate

A `.npy` diffed against CPython: a field from a class-instance global, the
method-call form (`self.k.m()`), the bind-to-a-local control, and the existing
literal-global cases from
`test/test_nilpy_field_from_module_global.npy` still passing.

## Resolution

**The ticket's central conclusion was wrong, and the control it recommended is
what showed it.** It concluded "the inference is not the missing piece; whatever
`self.k = G` stores is not the instance handle, and the read is off in both
lowerings." Run the control first, as the ticket itself advised:

```python
class C:
    def __init__(self):
        self.k: K = G       # EXPLICIT annotation
print(C().k.z)              # 9 — correct, and always was
```

The store and the read were fine all along. What was missing is the field's
**class identity**.

### Why bare `tyClass` produced 5887615

The pre-pass records two things per field: a kind (`tk`) and a record/class id
(`fldRec`). Every other arm sets both — the inline-construction arm does
`fldRec := REC_UCLASS_BASE + PyInferLastCi` right there. The module-global arm
called `PyModuleGlobalLiteralType`, whose return type is a bare `TTypeKind`, and
then set `fldRec := REC_NONE` — correct for a str/int/float/bool global and
exactly wrong for a class instance. So the field knew it held *a class* and not
*which* class, and `.z` read at the wrong layout. `tyVariant` printed 7 for the
same reason from the other direction: the tag was right, the payload was not an
instance the variant path could resolve.

That also explains why both attempts gave *plausible* numbers rather than
crashing, which is what made the original diagnosis so reasonable.

### Fix

`PyModuleGlobalCtorClass(name)` — the twin of `PyModuleGlobalLiteralType`, kept
separate precisely because its answer is a class INDEX, not a kind. The call
site sets `tk := tyClass` and `fldRec := REC_UCLASS_BASE + ci`, the same pair
the inline-construction arm sets.

One real trap inside it, caught by the repro still failing after the first
build: the whole-right-hand-side guard for a CALL is
`PyBlkRhsEndsAfterCall(lp)`, not `PyBlkRhsEndsAt(k)`. The latter asks whether
ONE token ends the statement, which `K()` never does — so it silently declined
every instance and looked like the recognition had not fired at all.

### Measured — the gate, item by item

| | pxx | CPython |
| --- | --- | --- |
| field from a class-instance global | 9 | 9 |
| the method-call form `self.k.m()` | 18 | 18 |
| the bind-to-a-local control | 9 18 | 9 18 |
| **identity** — mutate through the field, read the global | 10 10 10 | 10 10 10 |
| a non-construction RHS (`W = K(1).m()`) | 2 | 2 |
| the existing literal globals (str/int/float/bool) | unchanged | unchanged |

The identity row is the one worth having: it proves the field holds the
INSTANCE, not a copy, which is what "reads garbage" would have hidden even if
the number had come out right by luck.

`test/test_nilpy_field_from_module_global.npy` extended rather than duplicated —
same concept, same file — and its `.expected` refreshed. **Byte-identical to
CPython.**

The stale note in `PyModuleGlobalLiteralType` saying this shape is deliberately
not recognised has been rewritten to point at the new routine and record what
the 5887615 actually was; leaving it would have sent the next reader down the
path this ticket just closed.

Gate: `gate.sh quick` GREEN (self-host fixedpoint + `--tier quick` + FPC seed
canary). Parser only, no frozen builtin, so no re-pin.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
