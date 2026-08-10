---
track: N
prio: 60
type: feature
blocked-by: []
status: done
owner: claude-AN
---

# A class used as a VALUE: `cls = A; cls(3)`

**Re-filed from Track U on 2026-08-10 (was
`decide-nilpy-class-as-value-dispatch-strategy`). There is no decision to make.**
The U ticket asked the user to choose between compile-time candidate dispatch,
an RTTI runtime marshaller, and a second all-variant ctor entry point. All three
are reinventions of machinery NilPy already ships. See the CORRECTION section of
that ticket for the full walk-back; the short version is below.

## Why it is not a design question (measured at `75390cfe2`)

NilPy's day-1 rule already covers this: **infer a static type where you can,
fall back to a variant where you cannot.** Both halves exist and are gated:

| situation | what happens today |
| --- | --- |
| call sites agree — `A(3)`, `A(7)` | specialised: ctor takes a raw Int64 |
| call sites conflict — `Poly(3)`, `Poly("x")` | **widened to a variant — works** |
| a def used as a value — `g = fa; g(10)` | **widened by `PyDefUsedAsValue` — works** |
| a method used as a value — `cb = self.on_key` | **widened at pyparser.inc:21998 — works** |
| a CLASS used as a value — `cls = A` | refused |

So all three ingredients are present:

- widening params/result to variants — `PyDefUsedAsValue`, and the method arm at
  pyparser.inc:21998;
- a ctor with variant parameters — that is exactly why `Poly` above works;
- constructing a class chosen at run time — `AN_METACLASS_NEW` already reads
  instance size and VMT from the RTTI blob.

**What is missing is the TRIGGER.** The method arm reads

```pascal
if (not fieldsOnly) and (not isCtor) and PyMethodUsedAsValue(origName) then
```

and `PyMethodUsedAsValue` keys on a METHOD name — but nobody writes
`cb = obj.__init__`. The signal for a constructor is *the CLASS name appearing
as a bare value*, and no scan looks for that. So the widening never fires, the
ctor stays specialised on a raw Int64, and `parser.inc:4444` refuses rather than
emit a mismatched call.

The `not isCtor` there is incidental, not a barrier: it arrived with
`2531e5398` ("a bound method taken as a value returns its result"), a fix about
bound methods, where a ctor genuinely is not one. (The other `not isCtor` guards
nearby are about RETURN types and are legitimate — a ctor does not return.)

## The rule, stated the way the language already works

**If we can prove a static type, specialise. The moment we cannot prove it, the
class is DIRTY and the parameter is promoted to a variant.** `cls = A` is simply
a third way of losing the proof, alongside conflicting call sites and `setattr`.

That is not a new rule and not a new mechanism — there is already a FAMILY of
whole-module token scans that do exactly this, and pyparser.inc's own comments
contrast them with each other:

| scan | asks | effect |
| --- | --- | --- |
| `PyDynAttrEverAssigned` | does anything write `x.nm = ...`, or call `setattr` AT ALL? | attribute access goes dynamic |
| `PyDefUsedAsValue` | is this def's name used as a bare value? | widen its params + result |
| `PyMethodUsedAsValue` | is `<something>.nm` read without calling it? | widen its params + result |
| **`PyClassUsedAsValue`** | **is this class's name used as a bare value?** | **widen its `__init__`** |

Note how coarse the existing ones already are: `PyDynAttrEverAssigned` returns
True if the token `setattr` appears anywhere in the module, for any name. The
dirty flag is deliberately blunt, and the cost is boxing, not correctness.

### The closed-world "cost" is not a cost

The superseded U ticket listed "assumes whole-program compilation" as a strike
against one of its options. It is not a new assumption: all three scans above
are already whole-module and already load-bearing, and `PyDefUsedAsValue`'s own
comment discusses the cross-module case explicitly. The genuine edge is
`eval` on input unknown at compile time — and pxx is a compiler, so that edge is
out of scope by construction, not by oversight.

## Plan, in landable stages

1. **`PyClassUsedAsValue(name)`** — mirror `PyDefUsedAsValue`: scan
   `MainProgramTokCount` for the class name as a bare value (not the `class`
   line, not `A(...)` construction, not `isinstance(x, A)`, not `except A:`,
   not an attribute). Those four already have their own intercepts and must not
   trip it.
2. **Widen the ctor when it fires** — lift the `not isCtor` exclusion for that
   case at pyparser.inc:21998 so `__init__`'s params become `tyVariant`, exactly
   as a conflicting call site would have done.
3. **Tag the value** — variant tag 11 (free; `VT_BOUNDFN_TAG = 10` is the last
   used), payload = the class RTTI blob address. `AN_CLASSREF` already exists
   (parser.inc:4452) and is built one line after the refusal.
4. **Call site** — `cls(args)` boxes the arguments as variants and constructs via
   the `AN_METACLASS_NEW` shape, reading size/VMT from the payload's blob and
   calling the now-uniform ctor.
5. **Lift the refusal** at parser.inc:4444.

Stages 1+2 alone make the single-class case (`cls = A; cls(3)`) work and are
independently testable; the registry case (`{"a": A, "b": B}[k](x)`) is the same
machinery once 3+4 land.

## Watch for

- **`self`** is params[0]; the method arm widens `for k := 1 to nparams - 1`,
  i.e. it already skips the receiver. Keep that.
- `PyMethodUsedAsValue` is keyed on the name alone so an override and its base
  stay in step. A class-keyed scan needs the same property across a hierarchy —
  if `A` is used as a value, a subclass's `__init__` must widen too, or the two
  disagree.
- `*args` / `**kwargs` indices (`mStarIdx`, `mKwIdx`) are excluded from widening
  in the method arm; mirror that.

## Unblocks

[[bug-nilpy-a-class-used-as-a-value-segfaults-or-refuses]] (N, 60),
[[bug-nilpy-calling-a-non-callable-segfaults]] (N, 55),
[[bug-n-a-type-name-is-not-a-first-class-value]] (N, 45) — though that last one
is partly the separate builtin-type-code question (`str`, `int`, `bytes` have no
RTTI blob), which this does not answer.

## Gate

`cls = A; cls(3)`, the two-class registry, a subclass whose base is used as a
value, and `*args` — each against CPython via `tools/pydiff.py run`.
`make test-nilpy` green + self-host byte-identical.

## Resolution (2026-08-10)

Landed as five pieces. The plan above held for stages 1, 2 and 5; stage 3 landed
as written; **stage 4 did not, and the reason is worth recording.**

### Stage 4's plan was wrong, measured

The plan said `cls(args)` "constructs via the `AN_METACLASS_NEW` shape … calling
the now-uniform ctor". `AN_METACLASS_NEW` reads instance size and VMT from the
blob at run time, but it calls the constructor either directly (a fixed proc
index) or through a fixed VMT slot — and **a NilPy constructor is given no
virtual slot at all**: pyparser's slot assignment reads
`if (not isCtor) and (not UMthIsStatic[mmi])`. So there is no slot number two
unrelated classes could agree on, and a fixed proc index would run A's
constructor on a value holding B — a silent wrong object, which is worse than
the refusal this ticket replaced.

What made it work with no new machinery: the class RTTI blob **already** carries
every method's name and code address, and pyeval **already** reflects a method
out of it and calls it through typed proc pointers (`PyFindMethCI` /
`PyHostCall`, the host bridge). Reflecting `create` is that same lookup, made
from the constructor. So the call site needed no compile-time change at all —
`cls(3)` already lowered to `pyvar_callv1`, and the classref arm goes there.

### What landed

1. **`PyClassUsedAsValue`** (pyparser.inc) — the missing TRIGGER, the fourth
   member of the family beside `PyDynAttrEverAssigned` / `PyDefUsedAsValue` /
   `PyMethodUsedAsValue`, and as coarse as they are. Excludes the shapes with
   their own intercepts: `A(...)`, the `class` header line (its name AND its
   base list), `isinstance`/`issubclass`, `except A:`, an import line, a `: A` /
   `-> A` annotation, `o.A`.
2. **`PyClassKinUsedAsValue`** widens the ctor over the whole line of descent.
   The **descendant** direction is the load-bearing one and is the one a first
   cut gets backwards: `PyClassRefNew` finds `create` by walking the PARENT
   chain, so `class D(A)` with no `__init__` of its own is constructed through
   **A's** constructor — widening only D would leave A's specialised on a raw
   Int64 reading a boxed variant as an integer.
3. **`VT_CLASSREF_TAG = 11`** (defs.inc), payload = the RTTI blob address. Its
   own tag is the whole point: a compiled def, a pyeval closure and a lifted
   bound-fn all ride as INTEGERS, so an untagged blob address was
   indistinguishable from a code address — which is exactly why `cls(3)` used to
   jump into the blob. The payload is static data, never a heap block, so the
   tag stays out of the variant clear/retain object-tag lists.
4. **One lowering site, not many** — `AN_CLASSREF` marked `ASTRight = 1` (set
   only at the lifted refusal, so the isinstance / `except` / class-method-
   receiver builders keep their raw pointer) boxes through `PyBoxClassRef`.
   Doing it there means assignment, list element, dict value, argument and
   `cls(...)` all work with no site of their own.
5. **`PyClassRefNew`** (pyeval.pas) allocates the dynamic class, stamps its VMT,
   and calls the reflected `create` — including the `*args` shape, whose packed
   TPyList slot is a class parameter and cannot ride in a Variant slot. The star
   index had no home in the reflected signature, so it now rides in bits 8..15
   of the RTTI method Flags word (`RTTI_METH_STARIDX_SHIFT`) — in Flags rather
   than a new field, so `lib/rtl/typinfo.pas`'s `TMethInfo` mirror is unchanged.
6. **Rendering** — `print(cls)` / `str(cls)` / f-string all print
   `<class '__main__.A'>`, byte-identical to CPython. All three of the render
   sites the tag-8/9/10 callable arm already occupies (plus `pyvar_repr`).

### Verified

`test/test_nilpy_class_as_a_value.npy`, wired into `make test-nilpy`, its
`.expected` generated by CPython: the single class, the two-class registry, a
subclass whose base is a value, a class passed as an argument, a class in a
list with `isinstance` still answering, a zero-arg ctor, a two-arg ctor, a
`*args` ctor, ordinary construction of a widened class, and the three renderings.
Gate: `tools/gate.sh quick` GREEN + `make test-nilpy`.

### Found while gating — filed, not fixed here

Three pre-existing bugs the gate cases walked into, each confirmed at `pinned`:

- [[bug-nilpy-a-fixed-parameter-before-star-args-segfaults]] — `(self, tag, *rest)`
  crashes; `(self, *args)` alone is fine.
- [[bug-nilpy-a-lowercase-name-is-hijacked-by-a-case-matching-class]] — `class F`
  makes `f(1, 2)` compile as constructing `F`. The old case-insensitivity
  landmine on a path the 2026-08 fix did not reach; it is why this test's holder
  names are deliberately non-colliding.
- [[bug-nilpy-a-method-call-on-a-callable-values-result-is-refused]] —
  `g(3).show()` is a parse error for ANY callable value, not just a class.

### Still open, deliberately

`bug-n-a-type-name-is-not-a-first-class-value`'s builtin half (`str`, `int`,
`bytes` have no RTTI blob to point at) is untouched — this answers only user
classes, as the ticket said it would.

## Log
- 2026-08-10 — resolved, commit 57a083c8f.
