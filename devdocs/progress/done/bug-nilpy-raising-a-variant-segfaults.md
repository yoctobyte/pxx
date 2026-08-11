---
summary: "`raise xs[0]` — raising an exception held in a VARIANT segfaults. `raise E(\"x\")` and `raise e` on a class-typed local both work, so only the variant-operand arm is broken; no diagnostic, and the crash is at the raise."
type: bug
track: N
prio: 55
found-by: claude-AN
status: done
owner: claude-AN
---

# Raising an exception held in a variant segfaults

- **Type:** bug (crash, no diagnostic) — Track N
- **Opened:** 2026-08-11, closing
  [[bug-nilpy-a-class-used-as-a-value-segfaults-or-refuses]]. That ticket's
  `raise cls(m)` row is this bug, not the class-as-a-value one: with classes as
  values landed, `cls("x")` CONSTRUCTS correctly and the crash moved to the
  `raise`.

## Repro

```python
class E(Exception):
    pass

xs = [E("a")]
try:
    raise xs[0]
except Exception as e:
    print("caught", type(e).__name__)
```

CPython prints `caught E`. pxx compiles clean and **SEGFAULTS**.

Confirmed pre-existing at `stable_linux_amd64/default/pinned` — it has nothing
to do with the class-as-a-value work, which is only how the shape was reached.

## The boundary, measured

| shape | result |
| --- | --- |
| `raise E("x")` | works |
| `e = E("x"); raise e` (class-typed local) | works |
| `raise xs[0]` / `raise cls("x")` — a VARIANT operand | **segfault** |

So the raise machinery is fine and the exception object is fine; what is missing
is the variant arm — the raise almost certainly takes the variant's 16-byte slot
where it wants the instance POINTER, and jumps through the tag word. That is the
same static-vs-variant split as
[[bug-nilpy-eq-dunder-skipped-when-either-operand-is-a-variant]] and
`project_nilpy_static_vs_variant_operand_paths_diverge`: the operand shape a
minimal test writes works, the shape real code writes does not.

## Fix shape

Unbox before raising: where `raise <expr>` lowers, a `tyVariant` operand needs
its object payload extracted (tag 7 → pointer) and a TypeError raised when the
tag is not an object, which is what CPython does for `raise 5`. Check the
`except` side too — `except cls:` with a variant class operand is the mirror
image and is likely to have the same hole.

## Gate

`make test-nilpy` + self-host byte-identical, with a `.npy` case covering
`raise xs[0]`, `raise d[k]`, `raise cls(msg)` through a class VALUE, a for-in
variable, `raise 5` (must be a catchable TypeError, not a crash), and the
`except` side; diffed against CPython.

## Resolution (2026-08-11)

The fix-shape section above was right about both halves, and the `except` mirror
it predicted is real (below).

### Fix

`raise <expr>` in `PyParseStatement` now unboxes a `tyVariant` operand to an
instance pointer before building `AN_RAISE`, through the existing
`PyUnboxVariantToClass` (pylib's `pyvarobj` + a class cast).

Unboxed to **Exception**, not to a specific class, and that is the point rather
than a shortcut: the static type is exactly what a variant does not have, and it
is not needed — handler matching reads the raised object's own VMT, so
`except F:` still selects on the runtime class. The base class is the honest
static answer.

In front of it, pylib's `pyraise_check(v)` passes the value through and raises
`TypeError: exceptions must derive from BaseException` otherwise — what CPython
does for `raise 5`. It tests **`is Exception`**, not merely "is it tag 7", and
that distinction is load-bearing: a LIST is an object too, so an
object-tag-only check let `raise [1]` through and an `except Exception` arm
then caught a raised `TPyList` as though it were an exception. Measured, not
assumed — the first cut did exactly that.

### Verified

`test/test_nilpy_raise_a_variant.npy` (`.expected` from CPython), wired into
`make test-nilpy`: a for-in variable, a list element, a dict value, a class
VALUE, a specific handler matching the runtime class, the five non-exception
kinds each as a catchable TypeError (list included), a raise inside a def, a
bare re-raise over a variant, and the two statically typed forms as controls.
Gate: `tools/gate.sh quick` GREEN + `make test-nilpy`.

### The `except` mirror — refused, not crashing, left open

```python
kc = E
try: raise E("x")
except kc as e: ...     # error: Nil Python: unknown exception class kc
```

A class VALUE as a HANDLER operand is a named refusal, at `pinned` too. That is
dynamic handler matching — a feature, not this crash — and a diagnostic is an
acceptable answer for it, so it is recorded here rather than opened as a bug.
It belongs with [[feature-nilpy-class-as-a-value]]'s remaining surface if
anyone wants it.

## Log
- 2026-08-11 — resolved, commit 4b3627a2a.
