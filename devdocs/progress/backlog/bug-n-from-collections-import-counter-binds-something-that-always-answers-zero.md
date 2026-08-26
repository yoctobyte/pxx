---
track: N
prio: 80
type: bug
blocked-by: []
summary: "`from collections import Counter` binds a name that SILENTLY answers 0 for every key instead of counting — `Counter('aab')['a']` is 0, CPython says 2. And `OrderedDict` from the same import is `undefined variable`. The consume-and-ignore rule promises an unsupported name walls VISIBLY at its use site; Counter breaks that promise by answering wrongly instead."
status: backlog
owner: frankonpiler-an
---

# `from collections import Counter` binds something that always answers zero

```python
from collections import Counter
c = Counter("aab")
print(c["a"], c["b"])     # pxx: 0 0        CPython: 2 1
```

```python
from collections import OrderedDict   # error: undefined variable (OrderedDict)
```

Both reproduce identically on `PXX_STABLE` and on HEAD — **pre-existing**,
found while fixing
[[bug-n-from-collections-abc-import-is-swallowed-by-the-collections-root-rule]]
and confirmed unaffected by that fix (the point of checking was that the
consumed arm had not changed; it had not, in either direction).

## Why this one is worse than the OrderedDict half

`PyImportIsConsumedOnly` consumes `from collections import ...` on a stated
promise, written in its own comment: *the names it exports that we support are
ordinary pylib symbols, and an unsupported name walls visibly at its use site.*

`OrderedDict` keeps that promise — `undefined variable`, loud, at the use site.
**`Counter` breaks it.** It binds to something that constructs without
complaint and then answers 0 for every key. That is the expensive failure mode
`devdocs/dev/debugging-playbook.md` opens with: a plausible wrong value far
from the cause, in code where a count of zero reads as "not present" and simply
takes the other branch.

So this is not "Counter is unimplemented". It is "Counter is half-implemented in
a way that lies", and the fix is either to make it count or to make it wall.

## Where to look

`PyStdAliasRecord` / `PyStdProvidesMember` (`compiler/pyparser.inc` ~32985) decide
which members of a consumed root get bound; pylib has `TPyCounter` constructors,
which is what the consume rule was counting on. Measure whether the binding
reaches `TPyCounter` at all, or lands on a same-named empty container — the
answer decides which of the two fixes applies.
