---
summary: "A NilPy CALL through a name that case-insensitively matches a class name is compiled as CONSTRUCTION of that class: `class F` plus `def f(a, b)` makes `f(1, 2)` fail with `Expected: )`. The value-position lookup was made case-sensitive in 2026-08; the call path was not."
type: bug
track: N
prio: 55
found-by: claude-AN
---

# A lowercase call name is hijacked by a case-matching class

- **Type:** bug (wrong name resolution; error or crash) — Track N
- **Opened:** 2026-08-10
- **Found by:** writing the gate cases for [[feature-nilpy-class-as-a-value]] —
  `s = S; s(1, 2)` crashed, and renaming `s` to `k` made it disappear.

## Repro

```python
class F:
    def __init__(self):
        self.n = 0

def f(a, b):
    return a + b

print(f(1, 2))
```

CPython prints `3`. pxx (also at `pinned`, so pre-existing):

```
Expected: ), but got:  (Kind: 80, Line: 8)
pascal26:8: error: unexpected token
```

`f(1, 2)` is compiled as constructing `F`, whose constructor takes no arguments
— hence the complaint about the second one. Rename the class to `Zed` and it
compiles and prints `3`.

## Why this is the OLD landmine, on a path the fix did not reach

`0f7ca1b7f` made the NilPy **value-position** class lookup case-SENSITIVE
(`PyIsClassTypeExact`) precisely so a local named like a class stops being typed
as that class — the lesson recorded there was that the fix had to go one level
down so every consumer moved together. The **call** path still reaches
`FindUClass`, which is Pascal-style case-insensitive, so it kept the old
behaviour. Same root, second site: the shape
`devdocs/dev/normalise-dont-special-case.md` warns about.

Python is case-sensitive; `f` and `F` are unrelated names, and no NilPy program
can want this. The lookup on this path should be exact-case too — check whether
`PyIsClassTypeExact` can simply be used here rather than adding a third rule.

## Also broken through the same lookup

```python
class S:
    def __init__(self, *args): self.n = len(args)
s = S
o = s(1, 2)     # SEGFAULT — `s(1, 2)` constructs S with a mismatched signature
```

which is why minimal NilPy repros should keep identifier names non-colliding
(`Zed`, `q`, `k`) — see `project_nilpy_name_matching_a_class_is_typed_as_that_class`.

## Gate

`make test-nilpy` + self-host byte-identical, with a `.npy` case covering a def,
a local and a parameter each named like a class in the other case, diffed
against CPython. Watch the genuine type positions (`isinstance(x, F)`,
`except F:`, an annotation) keep the case-INSENSITIVE lookup they rely on.
