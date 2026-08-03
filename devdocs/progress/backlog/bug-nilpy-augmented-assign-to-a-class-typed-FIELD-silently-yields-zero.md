---
track: N
prio: 45
type: bug
summary: "`h.acc += 5` on a class-typed FIELD silently yields 0 — the name-target twin is fixed; a dispatch written for the obvious site never fired, so the real code path is unknown"
---

# `obj.field += n` on a class-typed field silently yields 0

- **Type:** bug (NilPy, silent wrong answer) — **Track N**
- **Found:** 2026-08-03, fixing the NAME-target twin
  [[bug-nilpy-augmented-assign-on-a-class-instance-silently-yields-zero]]
  (fixed and gated). Same symptom, different code path.

## Measured

```python
class Acc:
    def __init__(self, v: int):
        self.v = v

    def __iadd__(self, o):
        return Acc(self.v + o)


class Holder:
    def __init__(self):
        self.acc = Acc(10)


h = Holder()
h.acc += 5
print(h.acc.v)          # CPython: 15     pxx: 0
```

`0`, no diagnostic. `self.acc += k` inside a method behaves the same. An
INT-typed field (`self.n += 1`) is correct, so this is specific to a
class-typed field.

## The useful part: where it is NOT

A fix was written and **backed out**, and that is worth recording so nobody
repeats it:

- the obvious home is the lhs-EXPRESSION augmented-assignment site in
  `PyParseStatement` (the `(CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind =
  tkDot)` branch, just after its `list += list` → `extend` special case);
- a `PyAugClassDunderNode` was added there, mirroring the working
  `PyAugClassDunder`, with the target CLONED rather than shared so that
  `h.acc` is not evaluated twice (sharing one subtree emits it twice);
- **it never fired.** A `writeln` probe at the top of that function produced no
  output at all for `h.acc += 5`, so the statement does not reach that site.

### A contradiction to resolve first

[[bug-nilpy-augmented-assign-to-a-variant-typed-field-corrupts-it]] (fixed
2026-08-02, `90eb6a85e`) states the field path IS "the same family as
`PyAugBinTok`'s handling in `PyParseStatement`, but on the field path" — i.e.
exactly the site the probe says is never reached for `h.acc += 5`. Both cannot
be true as stated. Most likely a MODULE-level `h.acc += 5` and an in-method
`self.acc += k` take different branches, and only one is that site; the probe
run was module-level. **Check both spellings separately before touching
anything.**

That ticket also names the right tool for it: `PXXDBG=a.ast:<Class>.<method>`
on the augmented spelling versus the explicit `self.n = self.n - amt` one
answers this in a single run, no probe rebuild needed. Its sibling
[[bug-nilpy-augmented-assign-of-a-variant-param-to-an-int-field-adds-one]] is
the same area and worth reading first.

So the first task is **find the path that actually handles an augmented
assignment to a field** — candidates not yet checked: an earlier dynamic-attribute
or `self.`-specific branch, or the typing pre-pass claiming it. Once the site is
known the dispatch is a ten-line twin of `PyAugClassDunder`: in-place dunder
(`__iadd__`…), else the binary one (`__add__`…) with a rebind, else raise
`PyUnsupportedOperandError` at run time. Keep the clone-don't-share rule: a
target like `f().acc += 1` must not call `f()` twice.

## Gate

A `.npy` diffed against CPython: `+=`/`-=`/`*=`/`//=`/`%=` on a class-typed
field, both at module level (`h.acc += 5`) and inside a method (`self.acc +=
k`); with only the binary dunder declared; with neither (must RAISE, catchable);
plus an int field and a list field, which must be unchanged.
