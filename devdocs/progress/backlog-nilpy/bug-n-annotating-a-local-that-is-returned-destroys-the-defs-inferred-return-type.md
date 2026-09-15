---
track: N
prio: 80
type: bug
blocked-by: []
summary: "`t: Holder = Holder(); return t` types the CALLER's local as a variant where the unannotated `t = Holder()` types it correctly — the annotation makes the inference worse, and only at the call site. `return self.m()` is the same scan's second blind spot."
---

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
