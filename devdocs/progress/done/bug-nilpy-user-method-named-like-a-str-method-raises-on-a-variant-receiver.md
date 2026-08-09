---
track: N
prio: 55
type: bug
status: done
owner: agent-AN
---

# A user method named `find`/`index` raises AttributeError when the receiver has no static class

```python
from dataclasses import dataclass, field

@dataclass
class N:
    tag: str
    kids: list = field(default_factory=list)

    def find(self, t):
        for c in self.kids:
            c.find(t)          # <-- AttributeError: 'N' object has no attribute 'find'
        return "done"

N("a", [N("b")]).find("a")
```

CPython prints `done`. pxx raises **AttributeError naming a method the class
plainly declares** — the most confusing possible message, because the attribute
IS there.

## The name is the whole variable

Identical bodies, only the method name changed:

| name | result |
| --- | --- |
| `find`, `index` | **AttributeError** |
| `count`, `get`, `render`, `walk`, `visit`, `rec` | correct |

It is not recursion, not arity, not `@dataclass`, and not the method table:
`d.find("x")` on the same class works when `d` has a **static** class. It breaks
only where the receiver is dynamically typed — here `c`, the loop variable over
a `list`-typed field, which is exactly how tree/DOM code is written.

## Cause — measured

`PyStrMethodInfo` (pyparser.inc) is the str-method table, and `find`/`index` are
rows in it. For a variant receiver the desugar takes **str-first priority**: it
hoists the receiver, guards on `pyvar_is_strtag`, and when the tag is NOT a
string calls `pydynattr_no_method` — i.e. it **raises** rather than falling back
to the user class.

`PyStrMethodLosesToClass` is the existing escape hatch, but it is hardcoded to
exactly two names:

```pascal
Result := (CaseEqual(mname, 'title') or CaseEqual(mname, 'count')) and
          PyAnyClassDeclaresMeth(mname);
```

`title` and `count` were added when tkinter's `root.title("x")` and a container's
`count` hit this. Each new collision has been patched one name at a time; `find`
and `index` are the next two, and `split`, `strip`, `format`, `encode`,
`replace`, `join` are all waiting behind them. Counting mechanisms per concept:
this is one concept with a growing hardcoded exception list — the shape
`devdocs/dev/normalise-dont-special-case.md` warns about.

## The fix is NOT a third name in that list

The runtime tag test is already there and already knows the answer. The correct
shape is a genuine three-way dispatch at the point that guard already sits:

1. runtime tag is a string → the str method (unchanged, so no string behaviour
   moves — this is the property that makes the change safe);
2. else the receiver is a user object whose class declares that method →
   dispatch to it;
3. else → `pydynattr_no_method`, as today.

That is what CPython does (dispatch on the runtime type), it deletes the
hardcoded list rather than extending it, and it turns several latent collisions
green at once instead of one per report. `PyAnyClassDeclaresMeth` already exists
for the compile-time half, and `PyFindDunder` over the class RTTI is the runtime
half (see project memory on runtime dunder dispatch).

Do NOT simply widen `PyStrMethodLosesToClass` to every name a class declares:
that flips the priority for a receiver that really IS a string, which is what
"str-first priority ... is what the dynamically-typed corpus relies on" is
protecting. The tag test is what makes both correct at once.

## Found by

Compiling a realistic HTML-tree program (`Node.render()` / `Node.find(tag)`).
`render` worked and `find` did not, in the same class, on the same receiver
shape — which is what made the name the obvious variable to vary.

## Gate

`make test-nilpy` + self-host byte-identical, with a CPython-diffed test that
sweeps EVERY str-method name as a user-class method reached through a
dynamically-typed receiver (a list element, a `dict` value, an unannotated
parameter), plus controls proving a genuine string receiver still gets the str
method for each of those names.

## Recon 2026-08-09 — why the hardcoded list exists, and what the fix actually costs

Mapped the alternatives before writing any code. Recording them so the next
session does not re-derive them.

**Widening `PyStrMethodLosesToClass` to every declared name is wrong**, and the
reason is sharper than "it flips priority": the predicate already requires that
some class declares the name, so widening it would mean a program containing a
class with a `strip` method loses `x.strip()` on EVERY dynamically-typed string.
One of the two must lose at compile time, and which one is genuinely undecidable
from the source — which is exactly why `title` and `count` were added by hand
rather than by rule.

**A compile-time two-way choice cannot be right.** CPython dispatches on the
runtime type; any purely static rule is wrong for one of the two receivers.

**The obvious runtime lowering is blocked on argument parsing.** The natural
shape is a hidden temp and an `if pyvar_is_strtag(tmp)` with the str call in one
arm and the class call in the other, both storing into a variant result. The
statement hoisting, hidden temps and `AN_IF` all exist. What does not work is
that `PyParseStrMethod` PARSES ITS ARGUMENTS FROM THE TOKEN STREAM (and has
several bespoke shapes for it — the -5 / -6 / -9 cases). Building two calls
needs the argument chain parsed ONCE and shared, so either PyParseStrMethod
grows a "parse args, do not build" split, or the arguments are parsed generically
first and PyParseStrMethod is fed them.

**So the practical route is the runtime one named in the ticket**: dispatch in
pylib, where the receiver's tag and its class RTTI are both available at the
moment of the call, rather than choosing a branch in the frontend. That is the
same mechanism `PyFindDunder` already uses to call a user class's `__eq__` /
`__repr__` from pylib, and it is why this ticket belongs with
`feature-nilpy-runtime-method-dispatch-on-variant` rather than beside the
hardcoded list.

Not attempted this session: a half-done version would either break string
receivers or add a third hand-maintained name, and both are worse than the
current visible AttributeError.

## FIXED 2026-08-09 — dispatched at run time; the hardcoded list is gone

Implemented the three-way dispatch the ticket asked for, as **one more arm of
the runtime dispatcher that already existed** in `PyParseVariantMethod` (the one
that tells `TPyList.pop` from a user class's `pop`) rather than as new machinery.
`PyStrMethodLosesToClass` is now the general predicate — "this str-method name is
also declared by some user class" — instead of a two-name list, and the choice it
used to make at compile time is made at run time by a `pyvar_is_strtag` arm added
LAST, so it is the OUTERMOST test and a genuine string keeps str-first priority.

### Three things the recon had not found

The recon concluded the frontend route was blocked because `PyParseStrMethod`
parses its own arguments. That is true and was the smaller half.

1. **The real blocker was a hoisted guard, not argument parsing.** Before any arm
   is built, this function hoists `if not pyvar_is_objtag(recv) then
   pydynattr_no_method(...)` as a STATEMENT — so it runs before the dispatch
   expression is ever evaluated, and a string receiver raised there no matter
   what arms existed below. Widened to `objtag or strtag` when the name is a str
   method. This is why "just dispatch at run time" had not worked when tried.
2. **The static class-arity check rejected valid programs.** `s.find("b", 1)` is
   Python's optional-start form; with a class whose `find` takes one argument in
   the program, the arity check errored at COMPILE time before dispatch. That
   arity can only mean the str spelling, so it now builds the str call alone
   behind the tag guard. Found by the sweep test, not by the repro.
3. **`title` and `count` were broken in the OTHER direction all along.** Being in
   the hardcoded list meant a receiver that really was a string LOST the str
   method — silently, since the class arm just ran. So the list did not trade one
   bug for none; it traded one bug for a quieter one. Both directions are fixed
   by the same change, which is the "several latent collisions green at once"
   the ticket predicted.

### Shared, not duplicated

The str table maps one pylib proc per ARITY (`''`/`_from`/`_range`/`_chars`/`2`/
`n`) because `FindProc` is not arity-aware. Rather than re-derive that in the new
arm, it was split out of `PyParseStrMethod` as `PyStrMethodFinish` and both
callers use it — a second copy of that resolution is precisely the mechanism that
drifts. `PyStrMethodArityOk` is its companion: the arm is built SPECULATIVELY, so
it must ask whether an arity fits instead of erroring on it, and drop the arm when
it does not (`n.find(a,b,c,d)` on a class whose find takes four is a class call).
When the arm is dropped, the widened objtag guard puts its raise back, so the
widening can never turn a clean AttributeError into a wild dereference.

`encode` is excluded by name: its row SKIPS its arguments rather than parsing them
(the `-4` case, because `errors="replace"` is a keyword), so the class path cannot
produce an argument chain for it. It keeps the old str-first behaviour.

### Gate

- `test/test_nilpy_str_method_name_collides_with_class_method.npy` — twelve
  colliding names (`find index count title strip split replace upper startswith
  format ljust`, plus `join`) each called through ONE dynamically typed loop
  variable holding BOTH a user object and a string, plus the optional-window
  forms (`find(s,1)`, `find(s,0,2)`, `count(s,0,3)`) and the tree walk this was
  found by. Expectation is **CPython's own output**; matches byte for byte.
  Wired into `make test-nilpy`.
- `make compiler/pascal26` — self-host fixedpoint converged, byte-identical.
- `tools/gate.sh quick` — GREEN.
- Whole-suite HEAD-vs-pinned `.npy` sweep, 513 files: **0 regressions**; the 3
  HEAD diffs also differ under `pinned` (pre-existing: `delitem_dunder`,
  `input_eof_raises`, `select_stdin_ready`). `pinned` differs on 50 vs HEAD's 3,
  the extra one being this ticket's own new test.

### Left open deliberately

A str method and a class method of the same name that disagree on RETURN type
make the expression `tyVariant`, exactly as the existing mixed-return class arms
do. That is right, but it means `it.find(x)` in a program with a class `find`
returning a string is variant-typed where it used to be Integer — visible only if
something downstream needed the static type. No sweep test showed it.

## Log
- 2026-08-09 — resolved, commit PENDING-COMMIT.
