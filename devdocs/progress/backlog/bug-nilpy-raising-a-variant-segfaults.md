---
summary: "`raise xs[0]` — raising an exception held in a VARIANT segfaults. `raise E(\"x\")` and `raise e` on a class-typed local both work, so only the variant-operand arm is broken; no diagnostic, and the crash is at the raise."
type: bug
track: N
prio: 55
found-by: claude-AN
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
