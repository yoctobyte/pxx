---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`class StreamWriter(Codec, codecs.StreamWriter)` is refused — 'cannot flatten base class ... A second base must be a class defined earlier in this file; an imported or built-in one cannot be flattened'. NilPy flattens multiple bases, and the flattening only reads bases whose body is in the current file, so the mixin-from-a-module shape that stdlib codecs are built out of does not compile."
---

# Multiple inheritance where a base comes from another module

Found porting the `codecs` shim for [[feature-b-mimic-codecs-for-nilpy]],
against `stable_linux_amd64/default/pinned` **v339 /
f11e0ed9816edc1d57ef8ee6e6ab0e5b9885db6c**.

## Repro

```python
import codecs


class Codec(codecs.Codec):          # (hangs today for a separate reason -- see below)
    pass


class StreamWriter(Codec, codecs.StreamWriter):
    pass
```

```
error: Nil Python: cannot flatten base class StreamWriter — its body was not
seen. A second base must be a class defined earlier in this file; an imported
or built-in one cannot be flattened
```

A single imported base is fine (`class MyDec(mod.Base)` compiles and inherits
correctly, verified with both a hand-written Pascal unit and `mimic_codecs`).
The refusal is specifically about a **second** base that the current file does
not contain.

## Why the shape matters

This is verbatim `webencodings/x_user_defined.py`:

```python
class StreamWriter(Codec, codecs.StreamWriter):
    pass


class StreamReader(Codec, codecs.StreamReader):
    pass
```

and it is how CPython's own `encodings/*.py` modules are written, all ~100 of
them. "A local class plus a base class from the module that defines the
protocol" is the ordinary Python mixin idiom, not an exotic one — so this will
be met again by every stdlib-shaped module the compile-real-libraries campaign
([[feature-nilpy-thirdparty-libraries-as-targets]]) reaches.

## Note on the diagnostic

The message is good — it says what it cannot do and why — but it is reported
against **the wrong line**: with a `class MyDec(probeu.PBase)` earlier in the
file it pointed at that line instead of at the offending `class Both(Extra,
probeu.PBase)`. Worth fixing alongside; a wrong line number on a clear message
costs more time than a vague message on the right one.

## Fix shape

The flattening reads a base's member list out of the current file's AST. An
imported class's members are already known — they are in the symbol table, which
is where the single-imported-base path gets them from. Making the flattener use
the same source for both would remove the restriction rather than widen it,
which is the `normalise-dont-special-case.md` answer.

## Blocks

The `x_user_defined.py` half of [[feature-b-mimic-codecs-for-nilpy]]'s gate,
together with
[[bug-nilpy-class-named-after-its-imported-base-hangs-the-compiler]] — that file
needs both. `mimic_codecs` itself is unaffected and lands.
