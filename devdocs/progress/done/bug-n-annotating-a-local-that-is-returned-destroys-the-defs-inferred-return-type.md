---
track: N
prio: 80
type: bug
blocked-by: []
summary: "RESOLVED 2026-09-24: the return scan's local-binding readers now accept `name: T =` (PyLocalAsgEqIdx, five readers), and `return self.m()` resolves self from the enclosing class in both passes. Fixture asserts the caller's TYPE as a relation to the unannotated spelling."
status: done
---

## RESOLVED 2026-09-24 (frankb-12) — both blind spots fixed

1. **Annotated local.** The return-type scan's token readers matched only
   `name =`. New PyLocalAsgEqIdx finds the binding `=` for `name =` AND
   `name: T =` (the annotated form only at a statement boundary, via the
   class-attribute side's PyClsAttrEqIdx so the two readers agree), and it is
   wired into all five readers that answer "what was this local bound to":
   the bare-ident return chase, PyRetRecvClass (both arms), PyRetNameType, the
   bound-in-this-def check, and the nested-def result chase.
   PyLocalScalarTypeFrom was left alone: it bails (`ok := False`) on any shape
   it does not know, so it is conservative, not wrong.
2. **`return self.m()`.** PyRetMethodType found receivers only by chasing an
   assignment, and `self` is never assigned. It now resolves `self` from
   CurSelfClass, then PyInferSelfCi — the same two sources in the same order as
   PyInferExprType's `self.m(...)` arm, so the signature pass and the frame pass
   agree. A subclass override reached through the inherited method prints its
   own value (9). Still variant, unchanged and value-correct: a method called
   before it is DEFINED, and `self.m()` from a nested def.

Fixture: `test/test_nilpy_annotated_returned_local_keeps_the_class.npy`; the
Makefile row asserts the TYPE as a relation (b and c must equal a, a must be
tk=6). Red on pin v420, binary sha256 af40370a8a91 (b, c tk=22).


# Annotating a local that is returned destroys the def's inferred return type

Measured 2026-09-15 at `4452ec0631a97c02`, module level, nothing else in the
file:

```python
def mk_bare():
    t = Holder()
    return t          # caller's local: tk=6   (correct)

def mk_ann():
    t: Holder = Holder()
    return t          # caller's local: tk=22  (VARIANT)
```

`PXXDBG=n.locals` shows `t` itself is **`tk=6` in both**. The local is typed
correctly either way. What breaks is the DEF'S RETURN TYPE, and it breaks only
in the annotated spelling.

**The direction is what makes this worth 80.** An annotation is the thing a user
reaches for to make code faster, it is the documented lever, and here it silently
costs them the caller's type — which on arithmetic is the 25.8x variant path
(`bug-n-a-class-level-field-annotation-is-discarded-unless-the-class-is-a-dataclass`
carries that measurement). A local-annotation pass measured by counting `tk=22`
INSIDE the annotated function reads as a pure win while it pushes variants into
every caller. Nothing warns.

## Second blind spot in the same scan

```python
def r_selfcall(self):  return self.r_ctor()     -> caller: tk=22
```

A method whose body returns ANOTHER method's result does not infer, even when
the callee is in the same class and does infer on its own.

## What the scan already gets right — measured, so the fix is scoped

All of these infer `tk=6` with no annotation anywhere:

| return shape | result |
| --- | --- |
| `return Vec3(1.0, 2.0, 3.0)` | `tk=6` |
| `return self + o` (dunder) | `tk=6` |
| `return self * k` (dunder) | `tk=6` |
| `t = Vec3(...); return t` | `tk=6` |
| two branches, both `return Vec3(...)` | `tk=6` |
| `-> 'Vec3'` explicit | `tk=6` |
| **`t: Vec3 = Vec3(...); return t`** | **`tk=22`** |
| **`return self.r_ctor()`** | **`tk=22`** |

So the expression chase, the operator dunders and the multi-branch join are all
fine. Two shapes are not.

## Mechanism, read from source and NOT yet confirmed by a fix

`PyInferDefRetTypeScanInner` (`pyparser.inc`) handles `return <name>` by chasing
the name back to its assignment in the body. An annotated declaration puts
`: <annotation>` between the name and the `=`, so a scan keyed on the name being
followed by `tkAssign` does not match it and the chase falls through to the
variant default. That is the same shape `PyClsAttrEqIdx` exists to solve on the
class-attribute side — that helper deliberately steps over an optional
annotation to find the `=`, and its own comment says the two readers must agree
or "a field registered at one type and read at another". **The return scan looks
like the third reader that was never told.** Labelled as read from source rather
than measured, because I have not yet instrumented the chase itself.

## Provenance

Found while answering the lekkerzeilen seat's 4.9 ms question. Their ladder had
reached "annotate the hot locals" (26 -> 19 `tk=22` in the hot path) and this
defect means that pass can lose typing at the callers of any annotated local
that is returned — so it was worth interrupting them for before they shipped it.
Their own framing, which is better than the one I started with and is recorded
here because it generalises past both tickets: **the constructor types a FIELD
and helps a reader that reads the field; a reader that CALLS A METHOD needs the
method's return type instead; which of the two matters is a property of the
caller, not of the value type.**

Their measured ladder on real code, same compiler, for whoever picks this up:

| change | hot-path `tk=22` |
| --- | --- |
| nothing | 41 |
| 3 constructor-parameter annotations | 41 (zero) |
| + field stores annotated | 41 (zero) |
| + parameter annotations on 10 readers | 39 |
| + **4 return-type annotations** | **26** |
| 14 explicit local annotations (separate tree) | 19 |

Four return annotations bought thirteen where three constructor annotations
bought nothing. The return-type surface is the high-leverage one for
method-calling code, which is what makes the two defects above expensive rather
than academic.

## Log
- 2026-09-24 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 3c28b6e248.
