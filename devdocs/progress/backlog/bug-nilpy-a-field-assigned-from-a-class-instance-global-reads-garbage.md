---
track: N
prio: 40
type: bug
blocked-by: []
summary: "`self.k = G` where G is a module global holding an instance: typing the field from the global (either tyClass or tyVariant) compiles and then reads GARBAGE — 5887615 / 7 where CPython says 9. Today it is still the loud 'cannot infer' diagnostic, because typing it was measured and rejected; the value path is what has to be fixed before the inference can be extended"
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
