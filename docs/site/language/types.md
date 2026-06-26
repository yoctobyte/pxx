---
title: Types
order: 21
---

# Types

PXX implements a traditional Object Pascal type system: ordinals, real numbers,
strings, enumerations, records, and arrays. Every example on this page compiles
and runs on the pinned compiler.

## Ordinal types

Integers and the types built on them (`Byte`, `Char`, `Boolean`, enumerations).
`Integer` is 32-bit; `Int64` is 64-bit.

| Type       | Size  | Range                         |
| ---------- | ----- | ----------------------------- |
| `Byte`     | 1     | 0 … 255                       |
| `ShortInt` | 1     | -128 … 127                    |
| `Word`     | 2     | 0 … 65535                     |
| `SmallInt` | 2     | -32768 … 32767                |
| `LongWord` | 4     | 0 … 4294967295                |
| `Integer`  | 4     | -2147483648 … 2147483647      |
| `Int64`    | 8     | signed 64-bit                 |
| `Boolean`  | 1     | `False` / `True`              |
| `Char`     | 1     | a single byte                 |

Ordinal helpers: `Ord`, `Succ`, `Pred`, `Inc`, `Dec`, `Low`, `High`, `Odd`.

## Real types

`Single` (4-byte), `Double` (8-byte), and `Real` (alias of `Double`). Write with
a field-width/precision suffix:

```pascal
writeln(f:0:1);   { 3.5 }
```

## Strings

`string` is a managed, reference-counted, length-prefixed type — it grows
automatically and frees itself. `Length`, `Copy`, `Pos`, `IntToStr`, and `+`
concatenation all work on it.

## Enumerations

```pascal
type
  TColor = (cRed, cGreen, cBlue);
```

`Ord(cGreen)` is `1`. Enumerations are ordinals — usable in `case`, `for`, and
array indexing.

## Records

```pascal
type
  TPoint = record
    X, Y: Integer;
  end;
```

Access fields with `.`. Records are value types — assignment copies the whole
record. Variant records (a `case` part sharing storage) are supported.

## Arrays

**Fixed arrays** have a compile-time index range:

```pascal
var fixed: array[1..3] of Integer;
```

**Dynamic arrays** start empty and are sized with `SetLength`; they are
0-indexed and managed:

```pascal
var dyn: array of Integer;
...
SetLength(dyn, 2);
dyn[0] := 1;
writeln(Length(dyn));   { 2 }
```

## Putting it together

```pascal
program types_demo;
type
  TColor = (cRed, cGreen, cBlue);
  TPoint = record
    X, Y: Integer;
  end;
var
  i: Integer;
  b: Byte;
  f: Double;
  c: TColor;
  s: string;
  fixed: array[1..3] of Integer;
  dyn: array of Integer;
  p: TPoint;
begin
  i := -42;
  b := 255;
  f := 3.5;
  c := cGreen;
  s := 'pxx';
  fixed[1] := 10; fixed[2] := 20; fixed[3] := 30;
  SetLength(dyn, 2);
  dyn[0] := 1; dyn[1] := 2;
  p.X := 7; p.Y := 9;
  writeln(i, ' ', b, ' ', f:0:1, ' ', Ord(c));
  writeln(s, ' len=', Length(s));
  writeln(fixed[2], ' ', dyn[1], ' ', Length(dyn));
  writeln(p.X, ',', p.Y);
end.
```

Output:

```
-42 255 3.5 1
pxx len=3
20 2 2
7,9
```

## Next

- [Classes & interfaces](./classes.md)
- [Back to the language reference](./index.md)
