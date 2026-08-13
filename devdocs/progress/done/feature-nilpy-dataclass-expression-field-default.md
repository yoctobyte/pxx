---
track: N
prio: 40
type: feature
summary: "A @dataclass field default may only be a scalar literal, field(default_factory=list/dict) or a zero-arg lambda. An expression (`x: int = 2 + 3`) is refused; a plain class attribute with the same initialiser is evaluated"
status: done
owner: claude-A-N
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

## DONE 2026-08-13

`x: int = 2 + 3` gives 5; a string concatenation, a default naming a module
global, and a float expression all match CPython, and the refusal test is now a
VALUE test — the flip this ticket's gate asked for.

### Built on the evaluate-once half only

The ticket prescribed reusing the plain-class-attribute mechanism, and the
first cut called `PyEmitClassAttrExpr` directly. That compiled and then
**segfaulted on the ordinary read `p.x`**: the routine also registers the name
as a CLASS ATTRIBUTE — a shared slot with per-instance overrides — so the read
went down the override path instead of to the field. A dataclass field is a
real instance field; the two share the evaluation POINT and not the storage
model. So `PyEmitDcExprDefault` copies the half that transfers (evaluate once
at the class statement into a hidden global, `$dcdef.<Class>.<field>`) and
none of the half that does not, and `PyDcDefaultNode` reads that global per
construction.

Once, not per construction, is Python's rule and is why
`field(default_factory=...)` exists at all. The test pins it by REBINDING the
module global the default names and constructing again — the value must not
move. The existing `PYDC_FACTORY_EXPR` span-replay stays what it is: the
factory contract, fresh per construction, and the test asserts both contracts
side by side in one class.

### Deciding by the RUN, not the first token

Two of this feature's shapes failed in two different ways: the literal arms
claimed the `2` of `2 + 3`, and the ident arm rejected `BASE * 2` outright with
a `field()`/`lambda` message. Neither said "expression". The default kind is
now decided by scanning the whole run first — one literal token (or `-` and
one) is scalar, an opening `field(`/`lambda` is a factory, everything else is
an expression — and only then does the existing dispatch run.

### The bug that only a SECOND field showed

The run-scan first left the cursor one token PAST the line's newline, which the
loop's own line-skip then read as "skip to the next newline" — eating the
following field line whole. A class with ONE expression default worked
perfectly; a class with two registered only the first, and the second read as
`"g": no such member on this record/class`. Worth recording because the
one-field repro is the one you naturally write.

Test `test/test_nilpy_dataclass_expr_default.{npy,expected}` (`.expected` from
CPython) replaces `test_nilpy_dataclass_expr_default_fail.npy`; the Makefile row
flips from asserting the refusal to diffing the values. The other four dataclass
tests were re-run against their exact expectations.

Gate: self-host fixedpoint + `tools/gate.sh quick` GREEN (seed canary included).

## Log
- 2026-08-13 — resolved, commit b08d0e66d.
