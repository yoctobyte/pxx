---
track: C
prio: 70
type: bug
blocked-by: []
summary: "`char names[2][8] = {\"ab\", \"cd\"}` stored the low byte of the LITERAL'S ADDRESS into each row's first character instead of copying the string. Row 0 was one garbage byte, row 1 was empty, and strcmp/printf(\"%s\") read past them — silently, on a string table, which every C program of any size has."
status: done
---

# A string-literal row of a 2-D char array stored its address

- **Type:** bug (silent wrong data) — **Track C** (`compiler/cparser.inc`).
- **Found:** 2026-08-16, by a gcc-differential sweep over C dark corners.

## Measured (before)

```c
char s[2][8] = {"ab", "cd"};
for (int i = 0; i < 16; i++) printf("%d,", ((char*)s)[i]);
```

```
gcc:  97,98,0,0,0,0,0,0,99,100,0,0,0,0,0,0,
pxx: -74,-58,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,
```

Those two leading bytes are the low bytes of the two literals' addresses. So
`strcmp(s[0], "ab")` answered -90 and `printf("%s", s[1])` printed nothing.
Local and global were both wrong; `char b[8] = "ab"` (one dimension) was always
right, which is what kept this hidden — the 1-D form is the one everybody
tests.

## Root cause — the row is not a scalar, and both paths thought it was

A 2-D initializer reaches an element with the string literal as the current
token, and both of the two paths that can get there called their scalar leaf,
which is `ParseCExpr` — and `ParseCExpr` on a string literal correctly yields
its ADDRESS. Stored into a `char` element, that address is truncated to its low
byte. Two paths because a global and a local do not share this code:

- **global** — `CInitWalkArray`, which had the fill for a *record member*
  (`CInitFillCharArray`) but not for an array row;
- **local** — `ParseCLocalDeclAST`'s flattening pre-scan for `dimCount >= 2`,
  whose element branch is a bare `ParseCExpr`.

Braced rows (`{{"ab"},{"cd"}}`) enter each path one level deeper, so each site
has to place the row from the enclosing sub-aggregate's base rather than from
the current cursor.

## Fix

`CInitFillCharFlat` — the existing member fill, addressed by FLAT element index
— plus a string arm in each of the two element loops that computes the row's
extent (the product of the dims below the current brace depth, stepped out one
level when the row was itself braced), fills the characters, writes the
terminating NUL if the row has room, and leaves the rest of the row zero.

Same fill at both sites rather than two spellings of it; the record-member path
keeps its own copy only because it is addressed by field path rather than by
flat index.

## Result

`test/cstr_table_2d_rows.c` (14 assertions: global and local, plain and braced
rows, 3-D, a row with no room for the NUL, char-literal rows unaffected, the
rows still writable afterwards, and the row stride) returns 42 under both gcc
and pxx.

## Gate

`make compiler/pascal26` + the test + `tools/gate.sh quick` — GREEN.

## Log
- 2026-08-16 — resolved, commit PENDING-COMMIT.
