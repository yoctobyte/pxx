---
track: N
prio: 55
type: bug
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
