---
track: A
prio: 40
type: bug
blocked-by: []
summary: "Given overloads on Int64 and LongInt, an argument of any OTHER integer type — Integer, SmallInt, Byte, an untyped literal — selects the Int64 one. FPC selects LongInt for all of them (narrowest that fits). Only an exact type-NAME match picks LongInt, so Integer and LongInt behave differently despite both being 4-byte signed. Silent wrong values wherever an overload set exists to give a type its own width."
---

# Overload resolution widens to `Int64` instead of picking the narrowest fit

- **Type:** bug (wrong overload selected → wrong values) — **Track A**
  (shared overload resolution; Pascal surface, so P-adjacent, but it lives in
  the shared `parser.inc`/`symtab.inc` ground).
- **Filed by Track B** on 2026-08-14 while fixing
  [[bug-b-inttohex-of-a-negative-integer-prints-16-digits]], which that
  ticket's own "the fix" section assumed would just work. It does not — the
  library half landed and is still wrong, because the RTL cannot express the
  distinction the compiler will not honour.

## Measured — pxx vs FPC 3.2.2, same source

```pascal
program h3;
function F(v: Int64): AnsiString; overload;
begin F := 'int64'; end;
function F(v: LongInt): AnsiString; overload;
begin F := 'longint'; end;
var i: Integer; li: LongInt; si: SmallInt; c: Cardinal; b: Byte;
begin
  i := -1; li := -1; si := -1; c := 1; b := 1;
  WriteLn('Integer  -> ', F(i));
  WriteLn('LongInt  -> ', F(li));
  WriteLn('SmallInt -> ', F(si));
  WriteLn('Cardinal -> ', F(c));
  WriteLn('Byte     -> ', F(b));
  WriteLn('literal  -> ', F(-1));
end.
```

| argument | pxx | FPC (`{$mode objfpc}`) |
| --- | --- | --- |
| `Integer` | **int64** | longint |
| `LongInt` | longint | longint |
| `SmallInt` | **int64** | longint |
| `Cardinal` | int64 | int64 |
| `Byte` | **int64** | longint |
| literal `-1` | **int64** | longint |

`Cardinal` agrees, and it is the row that shows FPC's rule is not "narrowest
declared": `LongInt` cannot hold every `Cardinal`, so `Int64` is the narrowest
that FITS, and FPC picks it. Every other row diverges.

`SizeOf(Integer) = SizeOf(LongInt) = 4` in pxx, and the `LongInt` row proves the
narrow overload is reachable — so what selects it is the type **name**, not the
type. Two spellings of one 4-byte signed integer take different code paths,
which is the double-case smell in
`devdocs/dev/normalise-dont-special-case.md`.

## Why it is not cosmetic

An overload set on integer widths exists *precisely* to give each width its own
behaviour. Picking the widest silently defeats it, and the value is wrong rather
than the program failing:

```pascal
var i: Integer;
begin
  i := -1;
  WriteLn(IntToHex(i, 8));   { FPC: FFFFFFFF   pxx: FFFFFFFFFFFFFFFF }
end.
```

That is `bug-b-inttohex-…` and it is now **blocked on this**: `lib/rtl/sysutils`
declares the FPC family (`Int64` / `LongInt` / `LongWord`), and a `LongInt`
argument is fixed by it, but the overwhelmingly common `Integer` argument still
sign-extends into the `Int64` spelling. The RTL cannot work around it — adding
an `Integer` overload beside the `LongInt` one would be exactly the
compiler-appeasement CLAUDE.md forbids (in FPC they are the same type, so the
platonic declaration is the one that is there).

## Where to look

Whatever ranks candidates in the shared overload resolution: it appears to score
an exact type-name match first, then fall through to "any wider integer" without
ordering the wider candidates by width. The fix is to rank integer candidates by
(fits ? width : reject), narrowest-first, so an alias resolves like its
underlying type. Check `Cardinal`/`LongWord`/`QWord` stay put — that row already
agrees and must not regress.

**Sweep before closing:** the same question for the unsigned family
(`Byte`/`Word`/`Cardinal`/`QWord` overload sets), for `Single`/`Double`/`Extended`
sets, and for an alias declared by a user (`type MyInt = Integer`), which is the
same "name vs type" question one level out.

## Gate

The table above matches FPC on every row, `make test` + self-host fixedpoint,
and `bug-b-inttohex-…`'s own FPC diff (14 rows, `Integer` / `Int64` / `Byte` /
`Word` / `Cardinal`, digits above and below the natural width) goes green
without touching `lib/rtl/sysutils.pas` again.
