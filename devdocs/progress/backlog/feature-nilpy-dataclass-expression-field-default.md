---
track: N
prio: 40
type: feature
summary: "A @dataclass field default may only be a scalar literal, field(default_factory=list/dict) or a zero-arg lambda. An expression (`x: int = 2 + 3`) is refused; a plain class attribute with the same initialiser is evaluated"
---

# Dataclass field defaults cannot be expressions

- **Type:** feature (NilPy dataclasses) — **Track N**
- **Opened:** 2026-08-02, when the refusal replaced a silent wrong value.

## Today

```python
@dataclass
class P:
    x: int = 2 + 3
```

```
error: a dataclass field default must be a scalar literal,
field(default_factory=list/dict) or a zero-arg lambda — an expression default is
not evaluated, and silently using only its first token would be worse than
refusing it
```

Until that check landed this **compiled**, and `P().x` was **2**: the scalar path
claimed the first token and the rest of the line was skipped in silence. The
refusal is not the goal, it is the honest interim.

## Why the plain-class route already works and this one does not

A non-literal class attribute on an ordinary class is evaluated ONCE at the class
statement into a hidden `$clsattr.<Class>.<name>` global, and construction copies
it in. A dataclass default cannot reuse that: it travels as a FOLDED CONSTANT in
the `PyDc*` tables (`PyDcKind` / `PyDcIVal` / `PyDcSOff`), which is what
`PyEmitDataclassCtor` reads to build the generated constructor. There is no slot
for "an expression evaluated at class-definition time".

## Shape of the fix

The same hidden-global mechanism, plus a way for the PyDc tables to name it:

1. a `PyDcSym` parallel entry holding the hidden global's symbol (-1 = none), the
   way `ProcParamDefaultSym` was added for parameter defaults
2. `PyParseClass` evaluates the expression at the class statement — it already
   does exactly this for a plain class attribute (`PyEmitClassAttrExpr`)
3. `PyEmitDataclassCtor` emits a read of that global instead of the constant

Python's own semantics fall out of this and are worth stating, because they are
the reason a fresh-per-construction shortcut would be wrong: a dataclass default
is evaluated ONCE, at class definition — which is exactly why
`field(default_factory=...)` exists and why a bare mutable default is an error in
CPython.

## Gate

A `.npy` diffed against CPython: an int expression default, a string
concatenation default, a default naming a module global, all read from several
constructions to prove the value is shared and evaluated once; plus the existing
`field(default_factory=...)` and scalar-literal tests green, and
`test/test_nilpy_dataclass_expr_default_fail.npy` flipped from a refusal to a
value when this lands.
