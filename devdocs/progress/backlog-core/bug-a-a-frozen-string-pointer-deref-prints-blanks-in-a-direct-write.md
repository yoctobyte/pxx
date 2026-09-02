---
track: A
prio: 60
type: bug
blocked-by: []
found: 2026-09-02
found-by: frankB
owner: —
summary: "CAUSE CORRECTED 2026-09-02 -- my first analysis was WRONG and the bug is FOUR TIMES WIDER than filed. I reported this as a PShortString-specific prefix-offset mismatch (pointee tyShortString, cap+1, vs storage tyFixedString, cap+8). Measured after making those two names agree: the mapping WAS inconsistent and is now fixed, and THE BUG DID NOT MOVE. It is general to every frozen-string POINTER DEREF -- `var s: string[10]; p: ^string[10]; p := @s; WriteLn(p^)` prints blanks exactly like the ShortString spelling, where FPC prints the string. So the prefix mismatch was real but incidental; PShortString was simply the first spelling I tried. THE SHAPE THAT MATTERS IS UNCHANGED AND IS WHY THIS IS STILL WORTH A TICKET: only the DIRECT-WRITE path is wrong. `t := p^` and `Length(p^)` are both CORRECT for both spellings, and `lib/rtl/typinfo.pas` derefs RTTI name pointers exclusively as `result := ps^` -- the correct path. So an RTTI name test passes today, and would keep passing through that half after the byte-prefix flip: a guard that cannot fail, drawn from exactly the population the question is about. Assert the CHARS on the DIRECT path or this is invisible. Track A rather than P: the divergence is in deref codegen, not in the parser."
---

# `PShortString` derefs a `ShortString` at the wrong prefix offset

## Measured

```pascal
var s: ShortString; p: PShortString;
begin s := 'hello'; p := @s; WriteLn('[', p^, '] len=', Length(p^)); end.
```

                          pxx                    fpc
    WriteLn(p^)           ~1000 NUL bytes        hello
    Length(p^)            5                      5
    t := p^; WriteLn(t)   hello                  hello
    SizeOf(s)             263                    256

**The copy path is CORRECT and only the direct write is wrong**, which is what
makes this survive a casual test. `t := p^` reads the chars from offset 8 and
gets them right; `WriteLn(p^)` does not.

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
