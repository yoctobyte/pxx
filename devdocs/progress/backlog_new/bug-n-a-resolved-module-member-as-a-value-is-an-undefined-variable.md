---
track: N
prio: 70
type: bug
blocked-by: []
summary: "`import m` then `m.f(1)` compiles and runs, but `h = m.f` — the same member in VALUE position — is a COMPILE ERROR, `undefined variable (f)`, naming the attribute as if it were a bare name. Every value position fails the same way (assignment, dict value, `map(m.f, ...)`), so a module's functions cannot be used as callbacks at all. The import resolves; only the value position is broken."
status: backlog
owner: unassigned
---

# A resolved module member used as a VALUE is "undefined variable"

- **Type:** bug — **Track N** (Nil-Python frontend).
- **Found:** 2026-08-25 by frank1-N-alias, while sweeping callable-value shapes
  for [[bug-n-calling-through-a-function-alias-with-a-default-omitted-segfaults]].
  Not part of that bug: this one never reaches run time.
- **Measured at HEAD**, self-host fixedpoint.
- **CPython accepts and runs every shape below**, so it is a defect and not a
  dialect choice.

## Repro — two files

`m.npy`:

```python
def f(a, lo=7):
    return a + lo
```

`s.npy`:

```python
import m
print(m.f(1))        # 8   — fine
h = m.f              # error: undefined variable (f)
print(h(1))
```

## The boundary, one variable at a time

| shape | result |
| --- | --- |
| `m.f(1)` — module member in CALL position | **8, correct** |
| `from m import f as zz` … `zz(1)` | **8, correct** |
| `from m import bisect` (a module-level alias) … `bisect(1)` | **8, correct** |
| `h = m.f` — assignment | **compile error** `undefined variable (f)` |
| `{"k": m.f}` — dict value | **compile error** `undefined variable (f)` |
| `map(m.f, [1, 2])` — argument position | **compile error** `undefined variable (f)` |

So the import resolves perfectly well and the member is reachable — it is
**only** the value position that fails, and it fails at COMPILE time.

## Why this is not the unresolved-import ticket

It shares a *message* with
[[bug-n-an-attribute-on-an-unresolved-import-degrades-to-a-bare-name]] (N, p62)
— both say `undefined variable (<attr>)` — but the causes are opposite, and
reading this as a duplicate would send the fix to the wrong place:

- **That** ticket: the import **did not resolve**, so the base binds to nothing
  and the qualified name degrades to a bare one. The complaint is that the
  diagnostic names the attribute instead of the failed import.
- **This** ticket: the import **did** resolve — the very same member called one
  line earlier returns the right answer. Only the value-position lowering fails
  to find it.

Same symptom text, so grep will collide; different mechanism, so the fixes do
not. Worth checking whether one bare-name fallback serves both paths, because if
so it is a single normalisation and closes both
(`devdocs/dev/normalise-dont-special-case.md`).

## Why it matters

`m.f` in value position is how Python spells a callback drawn from a module:
`sorted(xs, key=mod.keyfn)`, `handlers = {"a": mod.on_a}`,
`map(mod.parse, rows)`. None of them compile. The `from m import f` spelling
works, so the workaround is real — but it is a workaround, and the failure is a
compile error naming a variable the programmer never wrote, which gives no hint
that the spelling is the problem.

Loud rather than silent (it never builds), which is why it ranks below a
wrong-value bug and above cosmetic work.
