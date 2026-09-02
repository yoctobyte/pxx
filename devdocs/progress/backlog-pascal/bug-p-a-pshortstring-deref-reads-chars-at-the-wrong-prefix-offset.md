---
track: P
prio: 60
type: bug
blocked-by: []
found: 2026-09-02
found-by: frankB
owner: —
summary: "`PShortString` is the ONE spelling that reaches tyShortString from ordinary source, and it already mixes the two prefix conventions: `var s: ShortString; p := @s; WriteLn(p^)` prints garbage where FPC 3.2.2 prints the string. `Length(p^)` is correct (5), so the deref reads the LENGTH right and the CHARS wrong. Cause: `ShortString` the type name maps to tyFixedString (8-byte length word, measured byte0=5 byte8='h', SizeOf 263), but `PShortString` maps its POINTEE to tyShortString, whose slot rule is cap+1 -- so the deref looks for chars at offset 1 while the storage has them at offset 8. Matters beyond itself: it is a LIVE, reachable instance of the exact hazard feature-p-implement-the-real-tyshortstring-byte-prefix-layout's step-1 audit is looking for, which makes it a positive control that already exists rather than one that has to be built."
---

# `PShortString` derefs a `ShortString` at the wrong prefix offset

## Measured

```pascal
var s: ShortString; p: PShortString;
begin s := 'hello'; p := @s; WriteLn('[', p^, '] len=', Length(p^)); end.
```

    pxx   [<252 spaces>] len=5     SizeOf(s)=263
    fpc   [hello]        len=5     SizeOf(s)=256

Raw bytes of `s` confirm the storage: byte 0 = 5, byte 8 = 104 (`'h'`). That is
the `tyFixedString` layout, an 8-byte NativeInt length word followed by chars.

## Cause: two names for one type disagree about its prefix

- `ShortString` as a TYPE NAME resolves to `tyFixedString` (255 cap, cap+8 =
  263). Nothing here is a shortstring in the classic sense.
- `PShortString` sets its POINTEE kind to `tyShortString`
  (`pasparser_lval.inc:6742`), whose `FrozenStrSlotSize` rule is cap+1.

So the deref believes the chars start at offset 1 and they start at offset 8.
`Length` survives because it reads the length word, which both conventions put
at offset 0 — it just disagrees about the width, and the low byte is the same
on a little-endian target for any length under 256. **That is why the bug reads
as half-working**, which is the shape that survives review.

## Why this is worth more than one wrong `WriteLn`

`tyShortString` is nearly unreachable today — `ShortString` does not produce it
and `string[N]` does not either. The producers are `PShortString`, the
`TypeInfo('shortstring')` name arms (`pasparser_expr.inc:4606`,
`pyparser.inc:46449`) and RTTI naming. **`PShortString` is the one that yields a
VALUE**, and it is already wrong.

That makes it a **ready-made positive control** for
[[feature-p-implement-the-real-tyshortstring-byte-prefix-layout]]: step 1 of
that plan is an audit for sites that assume an 8-byte prefix without going
through the named emit pair, and this is one, reachable from four lines of
Pascal. A control that already exists beats one that has to be built.

It also falsifies, mildly, the reading that steps 1-2 of that plan touch nothing
live: they change `tyShortString` codegen, and there is a live path into
`tyShortString` today. It is not a path that carries a `string[N]` CAPACITY, so
it does not disturb the capacity thread — see the note on
[[bug-p-a-string-n-element-loses-its-capacity-in-three-container-shapes]].

## Gate

`make test` + self-host + cross. Assert the CHARS, not just `Length` — `Length`
is correct today and would certify this as working.
