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
