---
track: N
prio: 45
type: bug
summary: "A bound-method VALUE off a module-level global raises AttributeError as soon as ANY def in the module READS that global by name — `gb = b.hit` fails while the direct call `b.hit(3)` works. (The original title blamed a name collision; that was wrong, see the 2026-08-07 re-narrowing.)"
---

# A global named like another class's ctor parameter breaks a bound-method value

```python
class C:
    def __init__(self, b):        # <-- parameter named b, stored as self.b
        self.b = b
    def m(self, x):
        return self.b + x

class Counter:
    def __init__(self):
        self.hits = 0
    def hit(self, n):
        self.hits = self.hits + n
        return self.hits

b = Counter()                     # <-- global named b
gb = b.hit                        # bound-method VALUE
print("b", gb(3))
```

```
Unhandled exception: AttributeError: 'Counter' object has no attribute 'hit'
```

CPython prints `b 3`. Rename the global to anything that does not collide and it
works. In the same file, `k = Counter(); g = k.hit; g(1)` succeeds — so the
class, the method and the value form are all fine; only the NAME differs.

Repro kept at `/tmp/coll_repro.npy` in the session that filed this; it is 16
lines and reproduces above verbatim.

## Pre-existing

Identical on `stable_linux_amd64/default/pinned`, so this is not new. Found
while fixing [[bug-nilpy-bound-method-of-a-temporary-receiver-segfaults]],
whose test happened to use `a` and `b` as instance names and so reported this
bug instead of its own.

## Narrowing already done — each ingredient ALONE is insufficient

Measured, all answering correctly:

| shape | result |
| --- | --- |
| class with a FIELD `self.b` (param named `q`) + global `b` | correct |
| class with a PARAM `b` (field named `z`) + global `b` | correct |
| param and field BOTH named `b`, global `b`, **direct call** `b.hit(3)` | correct |
| param and field both `b`, global `b`, **value form** `gb = b.hit` | correct (!) |
| all of the above **plus** `C` having a method that reads `self.b`, and `Counter` having an `__init__` | **FAILS** |

So the minimal repro is not the obvious one: the collision alone does nothing,
and the bound-method value alone does nothing. The last row is where it tips,
which points at the pre-pass that types globals rather than at the value form
itself — but the exact ingredient was not isolated, and the four passing rows
above are the useful part of that hunt, not a conclusion.

## Related, probably the same family

[[project_nilpy_name_matching_a_class_is_typed_as_that_class]] — a param/local/
field named like a CLASS was typed AS that class, fixed with a case-sensitive
value-position lookup. This is the mirror: a GLOBAL named like a class's
member/param. Whatever types module-level names in the pre-pass is the place to
look, and the lesson from that fix applies directly: **when narrowing, vary the
NAMES as a dimension** — a test whose variables happen to collide reports
somebody else's bug.

## Gate

Per-fix loop, plus a `.npy` test that deliberately uses colliding names across
a global, a ctor parameter and a field, diffed against CPython.

## 2026-08-07, same day — THE TITLE AND THE NARROWING ABOVE ARE BOTH WRONG

Picked this up an hour after filing it and narrowed properly. The ctor
parameter, the field, the name collision — **all red herrings**. The real rule
is much simpler and much broader:

> **A bound-method VALUE taken off a module-level global breaks as soon as ANY
> `def` in the module reads that global by name.**

Minimal repro, 8 lines, no classes involved on the reading side, no name
collision anywhere:

```python
def plain():
    return b            # <-- any def that READS the global

class Counter:
    def hit(self, n):
        return n

b = Counter()
gb = b.hit              # AttributeError: 'Counter' object has no attribute 'hit'
print(gb(3))
```

Delete `def plain` and it prints 3. The reader does not have to be a method
(`d3`), a nested def (`d4`) or a plain def (`d5`) — all three fail identically.

### The bisect that got there

| the def's body | result |
| --- | --- |
| `return x` (never mentions `b`) | correct |
| `return self.z` (a different name) | correct |
| `return self.b` | **fails** |
| `return b` (bare global read) | **fails** |
| no def at all | correct |

And the form matters: in the SAME failing file, the direct call `b.hit(3)`
answers 3 while `gb = b.hit` raises. So the class, the method and the global's
type are all fine — only the VALUE form breaks.

The compiler's own inference agrees it is fine: `PXXDBG=n.locals` prints
`<module> b tk=6 rec=1` — correctly typed as Counter — **identically in the
passing and failing cases**. So this is not a typing bug in the pre-pass; the
resolution at the `b.hit` value site is what diverges.

### Hypothesis, NOT confirmed — do not write this into a fix without measuring

`PyCellPromotable` (pyparser.inc ~14295) promotes a name to a frame cell when a
def captures it, and module-level names appear as `<module>` locals (skLocal),
so they are eligible. A promoted name is respelled `hidden^` by `PyMakeIdent`.
That would explain the shape exactly: the CALL path derefs correctly while the
bound-method VALUE path takes the raw pointer and hands `pybound_new` something
that is not the instance — hence a dynamic lookup that reports the right class
name and fails to find the method.

It fits every row above, and it is still a guess: nothing here measured
`SymCellPtr[b]`. Confirm that first — this family has a documented history of
plausible root causes that were wrong
([[bug-nilpy-bound-fn-closure-objects-are-never-freed]] cost four sessions to
one).

### Why this matters more than prio 40 suggests

"A module-level singleton plus functions that use it" is ordinary Python, and
the failure is a runtime `AttributeError` on a line that looks correct. Worth
re-rating once the cause is known.

### The slug is now a misnomer

Kept anyway: it is already cited from
[[bug-nilpy-bound-method-of-a-temporary-receiver-segfaults]] and from a comment
in `test/test_nilpy_bound_method_value_receiver_shapes.npy`, and renaming it
would break both for no gain.

## ROOT CAUSE — DECLARATION ORDER. Measured, and the cell hypothesis above is WRONG

The cell theory is refuted: `PyPromoteCell` is called from exactly one place,
`PyPromoteNonlocalCells`, and only for names in an explicit `nonlocal`
statement. The repro has no `nonlocal`. Checked before writing it into a fix,
which is the only reason it did not become this ticket's third wrong cause.

The actual variable is **where the def sits relative to the assignment**:

```python
class Counter:
    def hit(self, n): return n

def plain():
    return b            # reads a global declared BELOW
b = Counter()
gb = b.hit              # AttributeError
```

Move `def plain` **below** `b = Counter()` and it prints 3. Nothing else
changes. That is the whole difference.

### It is worse than an AttributeError — the global is mis-REPRESENTED

```python
x = b
print(x.hit(3))         # SIGSEGV
```

So this is not about the bound-method path at all: copying the global into
another name and calling a method on THAT segfaults too. The bound-method value
was just the first shape that noticed. A direct `b.hit(3)` happens to work,
which is why the bug hides.

### Where to look

A def's body is parsed before the module-level assignment that gives `b` its
type has been seen, so the read resolves against a symbol that does not yet know
it is a `Counter`. `pyparser.inc` ~21142 — *"Create every module-level name the
type pre-pass found, BEFORE any def or class"* — is the machinery that exists to
prevent exactly this, so the question is why the pre-pass's answer is not the
one the def's read uses (or why the read creates its own symbol first).

This is the same shape as `PyClsAttrRedeclScan` and `PyClsAttrWriteScan`: a fact
about the whole module that a construct earlier in the file needs. Those are
whole-module TOKEN scans for that reason.

### Rating

Raised to prio 45 and it may deserve more. "Define functions, then the
module-level singletons they use" is ordinary Python and the failure is a
segfault or a wrong-looking `AttributeError` on a line that reads correctly.

### Status: parked with the diagnosis banked, not attempted

Handing over rather than guessing at a fix in the module-scope type pre-pass at
the end of a long session — the A/B above is sharp enough that the next session
should not need to re-derive anything.
