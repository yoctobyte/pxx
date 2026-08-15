---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`class StreamWriter(Codec, codecs.StreamWriter)` is refused — 'cannot flatten base class ... A second base must be a class defined earlier in this file; an imported or built-in one cannot be flattened'. NilPy flattens multiple bases, and the flattening only reads bases whose body is in the current file, so the mixin-from-a-module shape that stdlib codecs are built out of does not compile."
status: done
owner: claude-A-N-nightly
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

## Resolution (2026-08-15)

The fix shape in this ticket ("make the flattener read an imported class's
members from the symbol table") turned out to be the wrong lever. Flattening
replays a base's BODY TOKENS against the derived class, which is how a mixin's
methods get compiled against the host's layout; an imported class has compiled
procs bound to its OWN layout, so copying its member rows would give methods
reading the wrong offsets. There is nothing to widen.

The real lever is one level up: **which base becomes the Pascal parent is a
CHOICE**, and the code was making it unconditionally (always the first base).
An imported base can ONLY be the parent — nothing here can flatten it — so pick
it as the parent from wherever it stands and flatten the local ones. Nothing
about flattening changed.

**And the choice fixes the ORDER too, which is the half that had to come with
it.** C3 is left-to-right: in `class D(B, C)` B's members beat C's. A flattened
member becomes D's own and shadows the parent's, so flattening the LOCAL base
and parenting the IMPORTED one is exactly CPython's answer for the ordinary
`(local mixin, imported protocol)` shape. But `PyMixBuildSkip` had the parent
chain's names in the losing set unconditionally — correct while the parent was
always base #0, and backwards once it is not. First cut compiled
`class SW(Local, Protocol)` and answered `Protocol.Kind`, where CPython answers
`Local.Kind`: a silently wrong method, i.e. the one outcome this shape was being
refused to avoid. `PyMixBeforeParent[]` now records whether each flattened base
stands before the parent; only bases AFTER it lose to the parent chain.

Third site: `PyRegisterClassFieldsPrepass` set `UClsParent` from the first base
*before* it even looked for a comma, then deferred everything else. With the
parent now a choice, the two passes would disagree and the fields-only
registration would lay out over the wrong parent's size — so the pre-pass now
finds the comma first and defers the parent along with the rest.

Two imported bases are REFUSED (not half-taken): only one can be the parent and
the other's members would silently go missing.

The wrong-line complaint in the note above is fixed as a side effect — the
diagnostics now restore `TokPos` to the offending base's own token, so the
message points at the base it is about rather than at the class header.

**Oracle:** the test's every value is CPython 3's, byte-identical, on the
equivalent pure-Python hierarchy (`Before(Local, Protocol)` /
`After(Protocol, Local)` / a non-virtual override / the single-imported-base
case).

Tests: `test/test_nilpy_multiple_inheritance_imported_base.npy` +
`test/nilpy_units/mixinproto.pas`, and
`test/test_nilpy_two_imported_bases_fail.npy` +
`test/nilpy_units/mixinproto2.pas` for the refusal. Wired into `test-nilpy` and
`test-core`. The pre-existing `test_nilpy_multiple_inheritance` and
`test_nilpy_subclass_unit_base` are unchanged.

Gate: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick` GREEN.

## Unblocks

`x_user_defined.py` now has both halves it was waiting on — this and
[[bug-nilpy-class-named-after-its-imported-base-hangs-the-compiler]] (fixed
earlier the same day).

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
