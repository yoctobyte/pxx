---
track: N
prio: 75
type: bug
---

# NilPy string subscripts are 1-BASED — silently off by one vs CPython

Found 2026-07-19 while landing [[feature-nilpy-str-methods]] unit 2.
**Pre-existing; not caused by that change.** Silent wrong values, no
diagnostic — which is why this is filed urgent rather than backlog.

## Repro

```python
s = "Hello"
print(s[0])
print(s[1])
print(s[4])
```

| | s[0] | s[1] | s[4] |
|---|---|---|---|
| CPython | `H` | `e` | `o` |
| pxx     | NUL  | `H`  | `l` |

The subscript is being handed straight to Pascal's 1-based string indexing:
index 0 reads the slot before the first character (a NUL here) and every other
index is the previous character. `s[len(s)-1]` therefore reads the
second-to-last char, and the last char is unreachable.

## Why it matters for milestone 1

uforth uses 123 slice/subscript sites. Every one of them is silently wrong
today, and wrong in a way that still produces plausible-looking output — a
Forth tokenizer indexing word names one character early does not crash, it
mis-parses. Any .npy corpus result involving string indexing is untrustworthy
until this is fixed.

Note `TPyList` already implements Python semantics INCLUDING negative
indices (see pylib's `PyListFix`); only the string path was missed. That
asymmetry is the tell — the fix should route string subscripts through the
same convention, negative indices included (`s[-1]` is the last character in
Python).

## Scope

Also settle slices (`s[a:b]`) while here — uforth leans on them heavily, and
they share the convention. Check whether `for c in s` iterates correctly too.

## Fixed 2026-07-19

`s[i]` in PyExprMode now lowers to a pylib `pystr_at(s, i)` call instead of a
raw Pascal `AN_INDEX`. Doing the fixup in the RUNTIME helper rather than as
index arithmetic in the parser keeps the negative case correct without
evaluating the base twice (`s[-1]` needs `Length(s)`).

Semantics now match CPython: 0-based, negative counts from the end, and out of
range prints `IndexError: string index out of range` and halts — the same shape
as `TPyList`'s existing behaviour.

### Two files encoded the OLD behaviour and were ported

- `test/test_nilpy_str_param.npy` asserted `"ab"[1] == "a"`. Python says `"b"`.
  Its scanning loop was 1-based (`i = 1; while i <= n + 1`); now `i = 0;
  while i <= n`. Expectation updated `2\na\ncd\nok!` -> `2\nb\ncd\nok!`.
- `examples/shell/shell0.npy` (Track B/E file, ported out of necessity — the
  semantics change would otherwise leave the demo broken): four index sites in
  `tok`, `ap_wc`, `ap_upper`, `ap_rev`. `ap_rev` went from
  `i = Length(args); while i >= 1` to `i = Length(args) - 1; while i >= 0`.

That these two were the ONLY breakage is a useful signal about how little .npy
code depended on the old convention.

Gate: `test-nilpy` GREEN, `--tier quick` GREEN, self-host byte-identical,
`test_nilpy_str_methods.npy` (now including subscripts) diffed against CPython.

Follow-up filed: [[bug-nilpy-subscript-on-literal]].
