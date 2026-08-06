---
track: N
prio: 75
type: bug
status: done
owner: claude-AN
summary: "NilPy: `d[k] += 1` where the BASE is a variant (a nested container, or a local bound from one) computed the new value and never stored it — silently. The variant subscript route handled only a plain `=`; a statically-typed base took a different path and was already correct, which is what hid it."
---

# An augmented assign through a variant subscript is computed and dropped

- **Type:** bug (silent wrong value) — **Track N**
- **Found:** 2026-08-06, bughunting. Surfaced by a **record-aggregation
  program** — group records by category, count and sum per group — whose
  per-category counters all came out `0` while the per-category item LISTS were
  correct. Pre-existing.
- **Severity:** high. Nested counters, grids and matrices are everyday Python,
  and nothing raises.

## Measured (before, self-hosted at `88b8aeb94`)

```python
d = {"a": {"n": 0}}
d["a"]["n"] += 1
print(d)                        # CPython {'a': {'n': 1}}   pxx {'a': {'n': 0}}

grid = [[1, 2], [3, 4]]
grid[0][0] += 10
print(grid)                     # CPython [[11, 2], [3, 4]]  pxx [[1, 2], [3, 4]]
```

Three things bounded it, and together they name the cause:

```python
d["a"]["n"] = d["a"]["n"] + 1   # the PLAIN spelling works
d["a"]["n"] = 9                 # plain assignment through a variant base works
e = {"n": 0}; e["n"] += 1       # augmented on a STATIC base works
```

And it is not about nesting — a local bound from a container is the same
variant:

```python
inner = d["a"]
inner["n"] += 1                 # also dropped
```

## Cause

`compiler/parser.inc`, the variant-base subscript arm of `ParseLValueAST`:

```pascal
        if CurTok.Kind = tkAssign then
        begin
          Next; PyParseBoolExpr;
          node := PyMakeVariantSetItem(node, indexNode, CurASTNode);
          …
        end;
        node := PyMakeVariantGetItem(node, indexNode);
```

Only `tkAssign` — a plain `=` — was handled. An augmented token fell through to
the GETTER, and the enclosing augmented-assign machinery built a value with
nowhere to go. `PXXDBG=a.ir` shows it exactly: the flat case ends with the store
call, the nested case computes the result and emits **no store at all**.

A statically dict/list-typed base never reaches here — it goes through the
default indexed property, which
[[feature-nilpy-augmented-subscript-assign]] taught to desugar the
read-modify-write itself. That ticket fixed the path it could see; this is the
sibling route it did not.

## Fix

Handle the augmented tokens in the same arm, desugaring `v[k] op= x` to
`v[k] = v[k] OP x` with `PyMakeVariantGetItem` for the read and
`PyMakeVariantSetItem` for the write — the same shape the property path uses.

## Verified

`test/test_nilpy_augmented_subscript_variant_base.npy` (new, wired into
`make test-nilpy`): nested dict and nested list, a local bound from a container,
every augmented operator over a variant base (`+= -= *= //= %= <<= /=`, plus
`+=` on a str and on a list), the static-base controls, plain assignment, and
the record-aggregation shape that found it. All lines match CPython. The wider
probe corpus is unchanged and `tools/gate.sh quick` is GREEN.

## Known, pre-existing, NOT introduced here: the index is evaluated twice

```python
d["a"][key()] += 1     # CPython calls key() once; pxx calls it twice
```

The desugar re-evaluates the base and index expressions, so a side-effecting
index runs twice. **The statically-typed path already did this** — measured,
`e[key()] += 1` calls `key()` twice too — and
[[feature-nilpy-augmented-subscript-assign]] documents it as a deliberate trade
("the same trade the `del d[k]` rewrite makes"). The new arm matches the
existing behaviour rather than diverging from it; the VALUE is correct either
way. Filed on its own as
[[bug-nilpy-augmented-subscript-evaluates-its-index-twice]].

## Log

- 2026-08-06 — found by a real aggregation program, root-caused by bounding it
  against three working variants, fixed and verified in one pass.
