---
track: N
prio: 70
type: bug
blocked-by: []
summary: "`obj[k] += v` on any class that reaches subscripting through `__getitem__`/`__setitem__` is a named compile-time refusal — `augmented assignment to a __getitem__/__setitem__ subscript is not supported`. Ordinary Python, and the counting idiom (`counts[k] += 1`) is the single most common thing a dict-like class is written for. The default-indexed-property arm beside it already desugars the augmented form; only the dunder arm does not."
status: done
owner: agent-A
---

# An augmented subscript on a `__getitem__` class is refused

- **Type:** bug — **Track N**. **Found:** 2026-08-18 by frank2-7e while landing
  [[bug-n-a-builtin-subclass-subscript-operator-skips-the-override]].
- **Pre-existing**, not introduced by that fix — it is the dunder arm's own
  documented limitation (`compiler/parser.inc`, "Single-key subscript only (no
  `obj[a, b]` tuple key, no `+=` augmented form)"). What changed is its REACH:
  a builtin subclass now takes that arm too, so the refusal is visible to a
  shape that previously compiled (and silently called the base).

## Repro

```python
class Counts(dict):
    def __getitem__(self, k):
        return dict.__getitem__(self, k)
    def __setitem__(self, k, v):
        dict.__setitem__(self, k, v)

c = Counts()
c["a"] = 0
c["a"] += 1        # error: augmented assignment to a __getitem__/__setitem__
                   #        subscript is not supported
```

A plain user class with the same two methods and no base has always had this.

## Why it is a compile error and not a wrong value

Deliberate, and the reason it is filed at 45 rather than higher: the sibling
fix routes an augmented subscript to this arm **when either dunder is
declared**, so the alternative on the table was `c[k] += 1` silently calling
pylib's `store()` while the plain `c[k]` next to it called the override. A
named refusal beats a silent divergence, so the refusal is what landed. This
ticket is to finish the job, not to undo it.

## Shape of the fix

The default-indexed-property arm immediately above already does exactly this
desugar and is the model: `PyEvalOnce` the base and the key (Python evaluates
each once — `e[key()] += 1` calling `key()` twice was
`bug-nilpy-augmented-subscript-evaluates-its-index-twice`), build the read with
`PyCallMeth1(mci, '__getitem__', base, key)`, the binop with `PyAugBinTok` (or
`PyMakePow` for `**=`, which has no binary token — the third shape that keeps
needing its own arm), and the write with `PyCallMeth2(mci, '__setitem__', ...)`.
Requires BOTH members; a class declaring only one should keep a named error
saying which is missing.

While there: the same arm refuses a TUPLE key (`obj[a, b]`). Different feature,
same comment block — decide whether it goes in the same change or gets its own
ticket, but do not let the sibling sit unlooked-at
(`devdocs/dev/normalise-dont-special-case.md`).

## Gate

`make compiler/pascal26` fixedpoint + `tools/gate.sh quick`, plus the repro
above matching CPython, `**=` covered, the index expression evaluated exactly
once, and `test/test_nilpy_builtin_subclass_dunder_dispatch.npy` /
`test/test_nilpy_subclass_a_builtin_type.npy` unchanged.

---

## Resolved 2026-08-27

Done exactly as the ticket specified, and the ticket's "shape of the fix" was
right down to the helper names — `PyEvalOnce` the base and the key,
`PyCallMeth1(mci, '__getitem__', …)` for the read, `PyAugBinTok` / `PyMakePow`
for the combine, `PyCallMeth2(mci, '__setitem__', …)` for the write. The
default-indexed-property arm immediately above was the model and the whole
change is ~50 lines shaped like it.

The refusal is **finished, not undone**: the sibling fix that made this visible
routed an augmented subscript here whenever *either* dunder is declared, and a
named refusal was the right answer while the alternative was `c[k] += 1`
silently calling pylib's `store()` beside a `c[k]` that called the override.

### Measured — every augmented operator, against CPython

`+=` `-=` `*=` `//=` `%=` `**=` `&=` `|=` `^=` `<<=` `>>=` `/=` all agree,
including `**=`, which has no binary token in this frontend (it lowers through
`PyMakePow`, so `PyAugBinTok` returns `tkEOF` for it and `tkPowEq` is tested
explicitly — the third of the three augmented-assign target shapes to need its
own arm). The `Counts(dict)` repro from the ticket prints CPython's answer.

**The index is evaluated exactly once.** `s[key()] += 1` over a `key()` that
appends to a list prints `1`, not `2`. That is not incidental: the read and the
write both reference the base and the key, and an AST node referenced twice is
EMITTED twice — the identical trap the indexed-property arm one level up already
fell into (`bug-nilpy-augmented-subscript-evaluates-its-index-twice`).

### Half a protocol, and CPython's own words

An augmented store READS as well as writes, so it needs BOTH dunders — which the
ticket asked for as "a named error saying which is missing". Made a **run-time**
TypeError rather than a compile error, so `try: c[k] += 1 / except TypeError:`
still compiles, matching what the plain read and write arms beside it already
do. The messages are CPython's, character for character:

```
TypeError: 'OnlySet' object is not subscriptable
TypeError: 'OnlyGet' object does not support item assignment
```

### The sibling the ticket told me to look at, and the two it did not

- **The tuple key** (`obj[a, b]`) — the ticket asked me to decide whether it
  goes in the same change. It does not: it is a different feature (the arm must
  build a tuple and hand it to the dunder as one key), and it still errors by
  name, which is the correct state for an unimplemented feature. Left as it was.
- **The arm exists TWICE**, character for character, in `pyparser.inc` ~38087
  and `pasparser_lval.inc` ~1290 — the second half of it NilPy code living in
  the Pascal lvalue parser. Both copies were given the identical desugar,
  because which one a statement reaches depends on which lvalue parser its
  statement path entered and half-fixing is how a shape gets left behind. Filed
  as [[bug-n-the-dunder-subscript-arm-is-duplicated-verbatim-in-two-lvalue-parsers]]
  (p40) — it produces no wrong answer now that both agree, but it is primed.
- **A dynamically-typed receiver never reaches this arm at all.** Probing
  receiver shapes turned up three failures — a list element raises a TypeError
  CPython does not, a call result **compiles and silently discards the store**,
  and a construction corrupts the parse of a *later* statement. All three are
  identical at HEAD and at pinned v380, i.e. pre-existing and not this fix.
  Filed as
  [[bug-n-a-dunder-subscript-through-a-dynamically-typed-receiver-is-lost]]
  (p68) with the whole table; the witness test uses named receivers and says why
  in a comment.

### Gate

`make compiler/pascal26` (fixedpoint `3b22bda7226c`), `tools/gate.sh quick`
GREEN, `test_nilpy_builtin_subclass_dunder_dispatch` and
`test_nilpy_subclass_a_builtin_type` both matching their expected strings
unchanged (the two the ticket named), and a witness row
`test_nilpy_augmented_dunder_subscript` in `test-core` whose `.expected` is
CPython's own output. At pinned v380 it does not compile — the refusal fires on
line 21.

No pin needed: `compiler/builtin/**` is untouched.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.
