---
track: A
prio: 50
type: bug
blocked-by: []
summary: "`s := v` on a BOOLEAN variant yields the EMPTY STRING — VariantToStr has no arm for VType=4 and falls off its if-chain into ''. `writeln(v)` on the same variant correctly prints True, so variant->text has two renderers and only one of them knows about booleans. Silent wrong value, no diagnostic."
---

# Variant->string drops the boolean tag (empty string, silently)

- **Type:** bug (silent wrong value) — **Track A** (the helper is
  `VariantToStr` in `compiler/builtin/builtin.pas`; a builtin change needs a
  re-pin)
- **Found:** 2026-08-13, while probing FPC's variant conversions for
  [[bug-p-variant-to-int-and-char-conversion-diverges-from-fpc]].
- **Pre-existing** — reproduced against the PINNED compiler, so it is NOT from
  [[bug-p-a-typecast-of-a-variant-reinterprets-it-instead-of-converting]]. That
  fix does make it reachable through one more spelling (`String(v)`, which used
  to be a hard `Error`), which is how it surfaced.

```pascal
program vs;
uses variants;
var v: Variant; s: AnsiString;
begin
  v := True;
  s := v;                    writeln('assign  s=[', s, ']');
  writeln('writeln v=[', v, ']');
end.
```

| | FPC 3.2.2 | pxx (pinned, and HEAD) |
| --- | --- | --- |
| `s := v` | `True` | **`[]`** — empty |
| `writeln(v)` | `True` | `True` |

## Root cause

`VariantToStr` (builtin.pas ~604) tests VType 1/2 (int), 3 (float), 5 (char),
6 (string), 8193 (promo), 0 (None) — and has **no arm for 4, the boolean tag**,
so it falls through to the trailing `else Result := ''`. `VariantTagName` right
below it *does* know `t = 4` is `'a boolean'`, which is what makes the omission
look like a slip rather than a decision.

## The shape

Variant->TEXT has (at least) two independent sites: the `writeln` path renders
a boolean correctly, `VariantToStr` does not. Same concept, two mechanisms, one
of them with a hole — `devdocs/dev/normalise-dont-special-case.md`. **Before
closing, check whether the two can share one renderer** rather than adding a
fourth arm to the second copy; and grep for any other variant->text site (the
NilPy side has `pystr_of`, which is deliberately separate and spells tags
Python's way — that one is not a duplicate to merge).

Related: the same file's other missing-tag behaviour is worth a sweep while in
there — VType 7 (object) also lands in the `''` else.

## Gate

`make test` + self-host fixedpoint, then re-pin (`tools/testmgr.py --pin`) —
builtin changes do not reach the gate's fixedpoint until pinned. Add the repro
above to the variant tests, diffed against FPC.
