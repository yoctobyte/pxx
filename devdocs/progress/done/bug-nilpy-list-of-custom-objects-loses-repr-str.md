---
track: N
prio: 40
type: bug
blocked-by: []
status: done
owner: claude-N
---

# A user class instance boxed in a list/dict prints as empty, losing `__repr__`/`__str__`

Found by proactive CPython-diff sweeping. `print(p1)` on a bare, statically
class-typed local correctly calls `__repr__`/`__str__` (the compiler knows
`p1`'s class at compile time and emits a direct method call). But once the
SAME instance is boxed into a `TPyList`/`TPyDict` (as a `Variant` element, its
static class identity erased), printing the container renders each element as
an EMPTY string instead of calling the class's `__repr__`:

```python
class Point:
    def __init__(self, x, y):
        self.x = x
        self.y = y
    def __repr__(self):
        return f"Point({self.x}, {self.y})"
p1 = Point(1, 2)
p2 = Point(1, 2)
print(p1)          # Point(1, 2) -- correct
print([p1, p2])    # CPython: [Point(1, 2), Point(1, 2)]   pxx: [, ]
```

## Root cause

`pyvar_repr`/`pystr_of` (`compiler/builtin/pylib.pas`) dispatch on the
Variant's runtime tag: tag 7 (VT_OBJECT) is special-cased for `TPyList`/
`TPyDict`/`TPyBytes` only (`if o is TPyList then ... if o is TPyDict then ...`)
and everything else falls through to `pyrepr_of`/`VariantToStr`, which has no
concept of a user-defined class or its `__repr__`/`__str__` method — pylib.pas
is a plain runtime unit compiled once, with no visibility into classes a NilPy
program declares later.

This is the SAME underlying architectural gap as the already-open
`feature-nilpy-runtime-method-dispatch-on-variant` (confirmed still open,
2026-07-31 recon): a class instance that reaches pylib's runtime helpers only
as a bare Variant handle has no way to call back into its own class's methods
without new runtime type-dispatch machinery (test the receiver's class tag,
branch to its own `__repr__`/`__str__` VMT slot, fall back to the default
`ClassName(...)` object repr CPython itself uses when neither dunder is
defined). Filed separately since the container-print path is a distinct
manifestation from that ticket's method-name-ambiguity case, but any fix
belongs to the same runtime-dispatch effort.

Not attempted here — same class of problem the sibling ticket already scoped
as "new runtime type-dispatch codegen, not a quick patch."

## 2026-08-07 — the stated ROOT CAUSE is stale: runtime dispatch already works

Reproduced first (still exact: `[, ]` and `{'a': }`), then measured the premise
this ticket and its sibling rest on — *"a class instance that reaches pylib's
runtime helpers only as a bare Variant handle has no way to call back into its
own class's methods without new runtime type-dispatch machinery"*.

**That machinery exists and works today.** On a receiver whose class is
genuinely not known at compile time:

```python
class A:
    def __repr__(self): return "A!"
class B:
    def __repr__(self): return "B!"

def show(o):                 # untyped parameter -> variant
    return o.__repr__()

print(show(A()), show(B()))  # "A! B!"   correct

for m in [A(), B()]:         # heterogeneous list, element is a variant
    print(m.__repr__())      # "A!" then "B!"   correct
```

Both dispatch to the RIGHT class. So do `type(e).__name__`, `isinstance(e, Point)`
and `e.x` on an element pulled out of a list. pylib itself already calls
`TObject(obj).ClassName` on these pointers (pylib.pas ~2307, ~2331), so the VMT
is reachable from inside pylib too.

### So the gap is narrower than recorded

Not "no runtime type dispatch". It is: **the `__str__`/`__repr__` rewrite is a
COMPILE-TIME one**, keyed on the receiver's static class
(`pyparser.inc` ~10900, `FindUMeth(argCi, '__str__')`), and a container element
has no static class for it to key on. pylib's own renderer then has no route to
the dispatch that does exist.

### Design this unlocks — reuse the lowering instead of building new machinery

The frontend already knows how to build "call `__repr__` on this variant" — that
is exactly what it emits for `o.__repr__()` above. So:

1. pylib declares a hook, e.g.
   `PyUserReprHook: function(const v: Variant; wantRepr: Boolean): AnsiString`,
   nil by default, and its element renderer calls it for a tag-7 payload that is
   not one of pylib's own classes (`PyRecIsPylibOwnClass` is the existing
   predicate for that half).
2. The compiler synthesises ONE proc whose body is the AST it already builds for
   `o.__repr__()` / `o.__str__()`, with CPython's default-object fallback, and
   installs it into the hook — the same install-a-hook pattern
   `PXXObjFinalizeHook` already uses.

No new dispatch codegen; the missing piece is a route, not a mechanism.

### Not started

The change touches every container print, so it wants a session that can carry
it and re-run the container tests. Parked with the diagnosis corrected rather
than left resting on a premise that is no longer true — and the sibling
[[feature-nilpy-runtime-method-dispatch-on-variant]] should be re-read in this
light too, since it is scoped on the same stale assumption.

## RESOLVED 2026-08-08 — the route existed; it just was not taken

The 2026-08-07 correction was right: this needed a route, not a mechanism. The
class RTTI carries the method table and pyeval already looks a method up by NAME
in it (`PyFindMethCI`) and calls it through a typed pointer. pylib's renderer now
makes the same lookup.

Simpler than the design sketched above, which proposed a hook installed by a
compiler-synthesised proc. No hook and no synthesis: pylib gained `uses typinfo`
(no cycle — typinfo has no uses clause of its own) and does the lookup directly
in `PyUserObjStr`, called from `pyvar_repr` and `pyvar_print_of` for a tag-7
payload that is not one of pylib's own containers.

| expression | before | after |
| --- | --- | --- |
| `print([p1, p2])` | `[, ]` | `[Point(1, 2), Point(1, 2)]` |
| `print({"a": p})` | `{'a': }` | `{'a': Point(1, 2)}` |
| `print((p, p))` | `(, )` | `(Point(1, 2), Point(1, 2))` |
| `print([Plain(9)])` | `[]` | `[<__main__.Plain object at 0x...>]` |

`__str__` vs `__repr__` follows CPython: a bare `print(obj)` prefers `__str__`,
a CONTAINER renders its elements with `__repr__` — the test asserts the same
object answering differently in the two positions.

Only the zero-argument, AnsiString-returning shape is called — what
`def __repr__(self) -> str` compiles to. Any other shape falls through to the
old path rather than being invoked through a proc pointer whose ABI has not
been checked.

The no-dunder case now renders CPython's default `<__main__.Cls object at
0x...>` instead of the empty string. Not assertable line-for-line (it carries an
address), so the test checks its SHAPE — but an object silently vanishing out of
a printed container is the failure this ticket is about, and a shape with an
address in it is strictly better than nothing.

`test/test_nilpy_container_element_repr.npy` (new), oracle-diffed: list, dict,
tuple, nested list, a value that lost its static type through an untyped
parameter, both dunders on one class, and the no-dunder shape.

`tools/gate.sh quick` GREEN, self-host byte-identical, `make test-uforth` PASS.

### Note for the sibling ticket

[[feature-nilpy-runtime-method-dispatch-on-variant]] is scoped on the same stale
premise this ticket carried ("no runtime type dispatch exists"). It does exist,
and now pylib reaches it too. That ticket should be re-read before any work is
estimated against it.

## Log
- 2026-08-08 — resolved, commit 1f7a879c3.
