---
track: N
prio: 60
type: feature
blocked-by: []
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
