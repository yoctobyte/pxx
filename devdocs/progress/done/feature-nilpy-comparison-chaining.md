---
track: N
prio: 50
type: feature
---

# NilPy: comparison chaining (`0 <= i < n`)

Characterised 2026-07-20. Fails to parse — loudly, not silently.

```python
print(1 < 2 < 3)          # error: unexpected token
print("a" < "b" < "c")    # same
```

## uforth sites

Three, all the same shape and all bounds checks:

```
uforth.py:917    if 0 <= i < len(self.current_tokens):
uforth.py:4144   if 0 <= addr < len(vm2.memory):
uforth.py:4152   if 0 <= addr < len(vm2.memory):
```

## Shape

`a OP b OP c` means `(a OP b) and (b OP c)` with **b evaluated once** — that
single evaluation is the whole reason it cannot be desugared by repeating the
token text. `len(self.current_tokens)` in the sites above is a call, so a
naive `(0 <= i) and (i < len(...))` is fine for `i` but would evaluate the
call twice if the chain were the other way round.

The comparison layer is `PyParseIsCmp` in `pyparser.inc` — Track N. Bind the
middle operand to a hidden local first, the way the for-in desugar binds its
container (an IR value node is a SUBTREE, so reusing one RE-EMITS it).

## What already works, for the record

Single comparisons on every type, `==` on lists, and mixed int/float
comparison (`1 == 1.0` is True) all match CPython.

## Gate

`test-nilpy` green with a `.npy` case diffed against CPython — including a
chain whose middle operand is a CALL, which is where a repeat-the-text
lowering breaks + `--tier quick` + self-host byte-identical + `make fpc-check`.

## Log
- 2026-07-20 — resolved, commit c4d5ce4e.
