---
track: N
prio: 70
type: bug
blocked-by: []
summary: "`import m` then `m.f(1)` compiles and runs, but `h = m.f` — the same member in VALUE position — is a COMPILE ERROR, `undefined variable (f)`, naming the attribute as if it were a bare name. Every value position fails the same way (assignment, dict value, `map(m.f, ...)`), so a module's functions cannot be used as callbacks at all. The import resolves; only the value position is broken."
status: done
owner: agent-A
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

---

## Resolved 2026-08-27

### The boundary the ticket drew was exactly right, and it points at one line

`mod.f(1)` resolves through `ConsumeUnitQualifier` in `PyParseFactorCore`, which
consumes the qualifier and leaves the parser on the member — and then every
downstream arm that could resolve that member **needs a `(`**. With no argument
list the qualifier had still been consumed, so the member fell through to
ordinary *bare-name* resolution and missed. Hence `undefined variable (f)`,
naming an identifier the programmer never wrote alone; hence the ticket's
correct instinct that this reads as a scoping bug and is a spelling one.

The value-position arm right beside it — the one that turns a bare `f` into
Python's function object — declines a following `'.'` **on purpose**
(`str.lower` is a different construct with its own path). So `f`, `str.lower`
and `list` each had a callable-value arm and `mod.f` had none.

### Not the sibling ticket, and the ticket was right to say so

[[bug-n-an-attribute-on-an-unresolved-import-degrades-to-a-bare-name]] shares
the *message* and nothing else. Confirmed by measurement rather than by reading:
here the import resolves, `mod.f(1)` on the line above returns the right answer,
and the failure is one arm's guard. No bare-name fallback is shared between
them, so this is not the single normalisation the ticket hoped for.

### The fix

**One arm**, in `PyParseFactorCore` immediately after the bare-def one, through
the **same builder** (`PyMakeFuncValueFor`). Guards, in order: the member must
not be called (an ordinary qualified call is untouched), the qualifier must not
be a real symbol (a local named like a module keeps its field access —
`ConsumeUnitQualifier`'s own rule), the qualifier must name a unit, and the
member must resolve to a proc in **that** unit, exact case, because Python names
are case-sensitive and Pascal's proc lookup is not.

### The second implementation I wrote, and then deleted

The first cut put the arm in **`PyMakeFuncValue`** and widened the two
assignment sites' token-shape guard (they fire only when the name is the whole
RHS) with a shared `PyValueNameIsWholeRhs` predicate. It worked — for
assignment. `{"k": mod.f}`, `map(mod.f, xs)`, `key=mod.f`, `[mod.f]` and
`g(mod.f)` all still failed, because those positions never reach
`PyMakeFuncValue` at all.

Fixing `PyParseFactorCore` instead covers **all six**, assignment included: the
assignment path falls through to `PyParseBoolExpr` and lands on the same arm. So
the first cut was reverted in full — predicate, guards and arm — rather than
kept as a fast path. Two arms for one construct is precisely what
`devdocs/dev/normalise-dont-special-case.md` warns about, and the note above the
bare-def arm records this same function having already carried a *copy* of
`PyMakeFuncValueFor`'s body that drifted twice. Verified after the revert: every
shape below still passes.

### Measured — pxx against CPython, every shape

| shape | before | after |
| --- | --- | --- |
| `mod.f(1)` (control) | 8 | 8 |
| `h = mod.f` | compile error | 8 |
| `h = alias.f` (`import m as mm`) | compile error | 8 |
| `{"k": mod.f}` | compile error | 9 |
| `map(mod.f, [1,2])` | compile error | `[8, 9]` |
| `sorted(xs, key=mod.f)` | compile error | `[1, 2, 3]` |
| `[mod.f, mod.g]` | compile error | `12` |
| `g(mod.f)` (argument) | compile error | `11` |
| `str(h)` | — | `<function ` (a real function object, not an address) |
| `mod.CONST`, `mod.NAMES[1]`, `mod.Box(7)`, `C = mod.Box` (controls) | correct | unchanged |

### Gate

`make compiler/pascal26` (fixedpoint `46896b98b03f`), `tools/gate.sh quick`
GREEN, and a witness row `test_nilpy_module_member_as_a_value` registered in
**both** `test-nilpy` and `test-core` (so the quick tier carries it), reusing the
existing `nilpy_modhelper.py` sibling module. `.expected` is CPython's own
output. At pinned v380 it does not merely differ — it does not compile:
`undefined variable (twice)`.

No pin needed: `compiler/builtin/**` is untouched.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.
