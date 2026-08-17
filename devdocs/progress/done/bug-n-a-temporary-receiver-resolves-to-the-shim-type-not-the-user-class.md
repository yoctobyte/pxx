---
track: N
prio: 55
type: bug
blocked-by: []
summary: "After `import codecs`, a user class whose name matches a mimic_codecs TYPE (Codec, StreamReader, IncrementalEncoder…) is shadowed by the shim's type — but ONLY when constructed as a temporary inside an argument list. `f(x=Codec().m)` raises AttributeError while `z = Codec(); f(x=z.m)` works. Silent wrong name resolution, hits every real encodings module."
status: done
owner: frank2
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

---

## ROOT CAUSE + FIXED 2026-08-17 — a qualifier leaked into its own argument list

Re-measured at HEAD first, as this ticket asked: **reproduces exactly as filed**,
so nothing that landed since v344 had touched it.

### The mechanism

`PyCtorQualUnit` records which unit a QUALIFIED construction named, so
`codecs.CodecInfo(...)` resolves `CodecInfo` in `mimic_codecs` rather than by
first match (`feature-nilpy-qualified-class-construction`). It is set at
`parser.inc:10021`, and cleared only **after the whole construction expression
has been parsed** — arguments included.

`PyClassCreate` consults it first:

```pascal
if PyCtorQualUnit >= 0 then ci := FindUClassInUnit(name, PyCtorQualUnit);
```

So a nested `Codec()` in the argument list asked `FindUClassInUnit('Codec',
mimic_codecs)` and got the SHIM's row. The user's `__init__` never ran; the
object had no `m`; the failure landed at run time.

**A qualifier binds the one class name it precedes, never the constructions
nested inside that class's arguments.**

### The fix, and why it belongs where it is

`PyClassCreate` now clears `PyCtorQualUnit` immediately after resolving its own
name. The sibling flag two lines below already scopes itself exactly this way —
`PyCtorNoParens := False; { one construction only — never inherited inwards }` —
so this is the same rule applied to the flag that was missed, not a new one.
The call site still clears it after the expression, unchanged.

`pyparser.inc`, Track N. No Track A change was needed.

### Every cell of the shape matrix, and what each proved

| shape | before | after |
| --- | --- | --- |
| `codecs.CodecInfo(Codec().m)` | **AttributeError** | works |
| `codecs.CodecInfo(encode=Codec().m)` | **AttributeError** | works |
| `codecs.CodecInfo(StreamReader().m)` | **AttributeError** | works |
| `codecs.CodecInfo(encode=Zork().m)` — non-colliding name | works | works |
| `z = Codec()` then `codecs.CodecInfo(z.m)` | works | works |
| `g(Codec().m)` — user callee | works | works |
| `Codec().m(1)` / `f = Codec().m` | works | works |
| `codecs.Codec()` — the qualifier's actual job | shim's class | **still shim's class** |

The two "works before" rows are what identified the mechanism. A non-colliding
name works because `FindUClassInUnit` MISSES and the ordinary lookup answers; a
user callee works because no qualifier was ever set. So the bug needed a
qualified callee AND a name the qualified unit declares — which is exactly a
shim's vocabulary, and exactly what every real `encodings` module is built from.

### The ticket's framing was slightly off, and it matters for the next reader

"A temporary receiver in an argument" is too broad: `g(Codec().m)` with a plain
user callee was always fine. The variable is the **qualified callee**, not the
temporary and not the argument position. The temporary matters only because a
named receiver is constructed before the qualified call begins, so it never sees
the leaked flag.

### A second bug was suspected and DISPROVED — recorded so it is not re-chased

`codecs.Codec().decode` in an argument failed after the fix, which looked like a
nested qualified construction losing its qualifier. It is not: **the shim's
`Codec` class declares only a constructor** (`lib/rtl/mimic_codecs.pas:36`), so
`.decode` is correctly absent. Re-tested with a member that exists
(`codecs.IncrementalEncoder().errors` in an argument, alongside a colliding user
class): correct on HEAD **and** on pinned. There is no second defect.

That `codecs.Codec` lacks `encode`/`decode` at all is a `mimic_codecs` SURFACE
gap (Track B), not a resolution bug, and is not filed here.

### Test

`test/test_nilpy_qualified_ctor_does_not_capture_its_args.npy`, wired into
`test-nilpy`. **CPython is the oracle and agrees on every line.** Verified to
FAIL on the pinned compiler and pass at HEAD, so it is a real regression test
rather than a passing snapshot. It carries the controls too — a second colliding
name, a non-colliding name, the named receiver, and the user's class reached on
its own.

## Log
- 2026-08-17 — resolved, commit 95eb242c4.
