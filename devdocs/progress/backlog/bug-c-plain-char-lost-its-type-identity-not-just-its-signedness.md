---
summary: "Making plain char follow the psABI turned it into an 8-bit INTEGER, not a signed char: char fields now print as 104 instead of 'h', and _Generic loses its char association. Three gated tests red from one commit"
type: regression
track: C
prio: 70
---

# Plain `char` lost its type IDENTITY, not just its signedness

- **Type:** regression, three gated jobs — **Track C** (C frontend)
- **Filed:** 2026-08-03 by `claude@xeon` (Track T) from the `test-core` matrix.
  Handed over, not fixed.
- **Reproduces at HEAD** with a compiler rebuilt at `ff1a30aae`
  (first pass used a 2h-old binary and wrongly showed green — the numbers below
  are all from the rebuilt one).

## Three reds, one cause

| job | expected | actual |
|---|---|---|
| `test-core#src:test/test_c_struct_fields.pas` | `7 9 11 h i 3 4` | `7 9 11 **104 105** 3 4` |
| `test-core#src:test/test_c_packed_aligned.pas` | `X 42 8 4 P 7 5 1 A …` | `**88** 42 8 4 **80** 7 5 1 **65** …` |
| `test-core#src:test/cgeneric_selection_b209.c` | compiles | `pascal26:35: error: _Generic: no matching association and no default` |

104 is `'h'`, 88 is `'X'`, 80 is `'P'`, 65 is `'A'`. Every character-valued
thing now renders as its ordinal: `writeln` is picking an integer overload
because the value's type is no longer a character type.

## Mechanism

`07414aa89` *"fix(C): plain char follows the target psABI, and each target
predefines its own arch"* replaced

```pascal
    Result := base;              { plain char stays tyChar }
```

with a resolution to the target's signed 8-bit type. That fixes the thing it
set out to fix — `(char)-1 < 0` was folding inconsistently — but it conflates
two different properties:

- **signedness** is an *arithmetic* property: what `(char)-1` compares as, how
  it promotes;
- **type identity** is what `writeln` dispatches on and what `_Generic`
  matches.

C is explicit that these are separate: `char`, `signed char` and `unsigned
char` are **three distinct types** even though plain `char` has the same
representation and range as one of them. `_Generic` is the language feature
that makes this observable, which is exactly why the `_Generic` test broke.

For Pascal-side interop the same distinction is what makes a C `char` field
come out as a `Char` rather than an `Int8`, which is what the two `.pas` tests
assert.

## Blast radius — five gated jobs, one cause

Confirmed by running the shard against the corpus copied out of the watcher
clone (never inside it — it detaches HEAD underneath you):

```
test-c-conformance: 35 pass, 1 fail, 1 skip (of 37)
test-c-conformance: FAILURES: 00219.c(compile)
    pascal26:2805: error: _Generic: no matching association and no default
```

`00219.c:52` is `i = _Generic(i2, char: 1, int: 0);` — the same char
association, in the upstream c-testsuite battery rather than one of ours. It
fails identically on **i386**, so this is not an x86-64 psABI detail; it is the
type identity, on every target.

| job | how it fails |
|---|---|
| `test-core#src:test/test_c_struct_fields.pas` | prints ordinals |
| `test-core#src:test/test_c_packed_aligned.pas` | prints ordinals |
| `test-core#src:test/cgeneric_selection_b209.c` | `_Generic` no match |
| `test-c-conformance#shard2/6` | `00219.c` `_Generic` no match |
| `test-c-conformance-i386#shard2/6` | same, i386 |

The watcher auto-filed a stub per job; each now points here rather than being
triaged separately, and they will auto-close when this goes green.

## Suggested direction

Keep plain `char` its own type (`tyChar`) and carry the psABI signedness as an
attribute consulted by folding/comparison/promotion, rather than resolving the
type to `Int8`/`UInt8`. `-fsigned-char` / `-funsigned-char` then set that
attribute, which is also closer to what those flags mean in gcc/clang: they
change plain char's *behaviour*, not its identity.

The new `test/cchar_plain_signedness.c` that came with the commit should keep
passing under that shape — it tests the fold, not the identity.

## Gate

All three jobs above green, `test/cchar_plain_signedness.c` still exits 42, and
`_Generic` still distinguishes `char` / `signed char` / `unsigned char` as
three associations.
