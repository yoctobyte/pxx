---
track: N
prio: 55
type: bug
blocked-by: []
summary: "After `import codecs`, a user class whose name matches a mimic_codecs TYPE (Codec, StreamReader, IncrementalEncoder…) is shadowed by the shim's type — but ONLY when constructed as a temporary inside an argument list. `f(x=Codec().m)` raises AttributeError while `z = Codec(); f(x=z.m)` works. Silent wrong name resolution, hits every real encodings module."
---

# A temporary receiver in an argument resolves to the SHIM's type, not the user's class

- **Type:** bug (wrong name resolution → runtime AttributeError) — **Track N**
  (Python→IR lowering / NilPy name resolution). **Not Track B**: the
  `mimic_codecs` shim is correct, see "the shim is exonerated" below.
- **Found:** 2026-08-17 by frank3 (Track B), while picking up the
  `codecs.CodecInfo` gap reported against `webencodings`.
- **Measured against:** `stable_linux_amd64/default/pinned`, **v344**.
  Not re-checked at HEAD — Track B cannot rebuild the compiler. **Re-measure at
  HEAD before working it**, several N fixes have landed since v344 was pinned.

## Repro — three cells, one variable at a time

Only the class NAME differs between the first two; only the RECEIVER between the
last two. Everything else is byte-identical.

```python
# arg_C — OK
import codecs
class C:
    def m(self, x):
        return x + 1
ci = codecs.CodecInfo(encode=C().m)
print("built", ci.encode(1))          # built 2
```

```python
# arg_Codec — FAILS
import codecs
class Codec:                           # <-- name matches mimic_codecs.Codec
    def m(self, x):
        return x + 1
ci = codecs.CodecInfo(encode=Codec().m)
print("built", ci.encode(1))
# Unhandled exception: AttributeError: 'Codec' object has no attribute 'm'
```

```python
# arg_Codec_named — OK
import codecs
class Codec:
    def m(self, x):
        return x + 1
z = Codec()                            # <-- same class, named receiver
ci = codecs.CodecInfo(encode=z.m)
print("built", ci.encode(1))          # built 2
```

| user class name | receiver | result |
| --- | --- | --- |
| `C` | temporary, in the argument | ok |
| `Codec` | temporary, in the argument | **AttributeError** |
| `Codec` | named local | ok |

CPython builds and runs all three (`cpython: built 2`).

## What it is

`import codecs` maps to `mimic_codecs` (the compile prints
`note: codecs -> mimic_codecs (shim, subset)`). The shim's **type** names then
shadow user classes of the same name — but only along the path that constructs a
temporary receiver inside an argument list. `Codec()` there builds the *shim's*
`Codec`, which has no `m`, hence the AttributeError. Bind the instance to a name
first and resolution is correct, which is why this is a resolution bug and not a
lifetime or refcount one.

The error message is actively misleading: `'Codec' object has no attribute 'm'`
is TRUE of the object that was built, and the user is looking at a class where
`m` is defined three lines up.

## Blast radius — this is not an exotic shape

`lib/rtl/mimic_codecs.pas` exports six class types: `Codec`,
`IncrementalEncoder`, `IncrementalDecoder`, `StreamReader`, `StreamWriter`,
`CodecInfo`. **Those are exactly the names CPython's codec convention tells you
to use**, so any real encodings module collides on five of six.

`library_candidates/webencodings/webencodings/x_user_defined.py` — the module
that started this — defines `Codec`, `IncrementalEncoder`, `IncrementalDecoder`,
`StreamReader` and `StreamWriter`, then does exactly the failing construction:

```python
codec_info = codecs.CodecInfo(
    name='x-user-defined',
    encode=Codec().encode,     # <-- temporary receiver, colliding class name
    decode=Codec().decode,
    ...
)
```

Confirmed on a second name to rule out anything `Codec`-specific: a user class
named `StreamReader` fails identically.

## The shim is exonerated — do not "fix" it in Track B

- `import mimic_codecs` and calling `mimic_codecs.CodecInfo(encode=C().m)`
  **works**. Same unit, same constructor, same argument shape. Only the aliased
  `codecs` spelling fails.
- A hand-written Pascal unit with the same shape — a class constructor with
  seven defaulted `Variant` parameters, called from NilPy with a bound method of
  a temporary, positionally AND by keyword — **works** (`probeunit.Holder`,
  `probe7.H7`). So it is not defaulted Variants, not keyword passing, not
  parameter count, and not constructors in general.
- `CodecInfo`'s declaration is right: every callable member is a `Variant`
  because the values are Python objects, which is what the shim's own comment
  says and what the working cases confirm.

Renaming the shim's types would make the symptom disappear while leaving the
resolution bug live for every other shim, so it is explicitly the wrong fix.

## Not to be confused with the other webencodings blocker

Compiling `webencodings/__init__.py` against **v344** fails earlier and for an
unrelated reason — a relative import in a function body:

```
pascal26:81: error: undefined variable (from)
  near:  x-user-defined    from >>>  x_user_defined
```

from `if name == 'x-user-defined': from .x_user_defined import codec_info`.
That is fixed at HEAD (`a6d84f1c6`, `22da0d833`) but **not in the v344 pin**, so
Track B cannot reach past it. `x_user_defined.py` compiles clean on its own even
on v344 — the bug in this ticket is a RUNTIME failure, not a compile one.

## Gate

The three-cell matrix above: all three run and print `built 2`, matching CPython.
Then `x_user_defined.py` builds its `codec_info` without raising, and
`webencodings` imports (which additionally needs a pin carrying the relative-import
fixes).
