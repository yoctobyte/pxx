---
track: N
prio: 45
type: feature
---

# NilPy: a generator expression as a call argument

Hangs off [[feature-nilpy-corpus-uforth]]. uforth's wall at line 1286:

```python
wrapper = "def __body__():\n" + "\n".join(
    "    " + line for line in clean.splitlines()
)
```

`"\n".join(EXPR for VAR in ITER)` — a bare generator expression (no brackets)
in an argument position. List comprehensions LANDED (commit "list
comprehensions") but only at STATEMENT level (assignment RHS), where the
desugar can emit an empty-list init plus an appending loop as sibling
statements. A genexpr in an argument is an EXPRESSION that contains a loop,
which the single-pass AST has no statement-in-expression node for.

## Options

1. **Special-case `join(genexpr)`** — str.join already collects its argument;
   recognise a genexpr there and desugar it to the same TPyList-building loop
   the statement comprehension uses, materialised into a hidden temp before the
   join. Narrow but covers this one site.
2. **General expression-level comprehension/genexpr** — lift each into a
   synthesized nested function (how CPython compiles them), replacing the
   comprehension with a call. Free variables must be passed in. This is the
   real fix and also unblocks comprehensions in `return`, call args, etc.

Recommend (2) when comprehensions are next revisited, since (1) is a dead end
that only defers the problem.

## Note — the NEXT wall is bigger

Immediately after this, uforth.py:1289 is `exec(wrapper, env, ns)` — the
runtime Python evaluator described in [[feature-lib-pyexec]]. That is a whole
subsystem (parse-once AST + tree-walker), so this genexpr and pyexec should
probably be scheduled together: getting past 1286 only reaches 1289.
