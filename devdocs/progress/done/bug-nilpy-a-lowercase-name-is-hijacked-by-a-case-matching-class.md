---
summary: "A NilPy CALL through a name that case-insensitively matches a class name is compiled as CONSTRUCTION of that class: `class F` plus `def f(a, b)` makes `f(1, 2)` fail with `Expected: )`. The value-position lookup was made case-sensitive in 2026-08; the call path was not."
type: bug
track: N
prio: 55
found-by: claude-AN
status: done
owner: claude-AN
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

## Resolution (2026-08-11)

### The site the ticket guessed at was not the one

The ticket assumed the CALL path still reached `FindUClass`. It does not — the
call path was already exact via `PyIsExactCtorName`. A probe found the real
one in two builds:

**`parser.inc`'s NilPy shadow rule** — *"a user class named like a pylib
builtin shadows the routine"* — cleared `procIdx` on
`FindUClassInUnit(name, -1) >= 0`, a **case-insensitive** lookup. So `def f`
lost its own proc to `class F`, and the name then fell through to whatever
handles a class. `FindProc('f')` was answering correctly the whole time; it had
just been thrown away three hundred lines earlier.

That also explains why the symptom MOVED. Before classes became values the
leftover name hit the class-CAST branch and failed to parse (`Expected: )` on
the second argument); after, it became a `VT_CLASSREF` variant and the program
compiled clean and raised *"takes 0 positional arguments"* from the constructor
of a class it never named. Same collision, worse failure — which is why this
was worth fixing now rather than filing and moving on.

### Fix — one rule, at every site that looks a class up by name

Python is case-sensitive: `f` and `F` are unrelated names and neither shadows
the other. Three sites now say so, joining the two that already did:

| site | was | now |
| --- | --- | --- |
| the NilPy class-shadows-routine rule | `FindUClassInUnit` (insensitive) | `… and PyIsClassTypeExact(name)` |
| the class-CAST branch `Name(x)` | `IsClassType` (insensitive) | exact under `PyExprMode` — and Python has no cast syntax, so a genuine `F(...)` is already claimed by the construction intercept |
| the class-as-a-VALUE lookup | `FindUClass` (insensitive) | exact under `PyExprMode` |

with `PyIsClassTypeExact` (typing) and `PyIsExactCtorName` (construction)
unchanged. Five sites, one rule — the shape
`devdocs/dev/normalise-dont-special-case.md` describes, and the reason its own
advice is *grep for the sibling*: this family has now been fixed in three
separate sessions because each site was found alone.

### The FPC seed canary earned its place

`gate.sh quick` went RED on the first run — not on the self-host, which passed,
but on the FPC seed: `PyIsClassTypeExact` is called from `parser.inc`, which is
included **before** the `pyparser.inc` that defines it. pxx tolerates that; FPC
needs a forward. One line, and exactly the `bug-a-fpc-seed-drift-emitasmx64-forward`
shape the canary exists to catch.

### Verified

`test/test_nilpy_lowercase_name_vs_class.npy` (`.expected` from CPython), wired
into `make test-nilpy`: a def, a local, a parameter and two module globals each
named like a class in the other case, plus the class itself still constructing,
`isinstance`-ing, and working as a value, and the def still usable as a value.
The three sibling tests that pin the earlier halves —
`instance_named_like_its_class`, `local_named_like_a_class`, `case_sensitive` —
all stay green. Gate: `tools/gate.sh quick` GREEN + `make test-nilpy`.

## Log
- 2026-08-11 — resolved, commit 0f0027d01.
