---
title: Pascal basics
order: 41
---

# Pascal basics

A PXX Pascal program has a program header, declarations, and a main block:

```pascal
program demo;

var
  name: string;

begin
  name := 'PXX';
  writeln('Hello from ', name);
end.
```

Statements are separated with semicolons. The program ends with `end.`.

## Declarations

Common declaration sections are:

```pascal
const
  Answer = 42;

type
  TPoint = record
    X, Y: Integer;
  end;

var
  P: TPoint;
```

## Control flow

PXX supports the usual Pascal statement forms:

```pascal
if P.X = 0 then
  writeln('origin')
else
  writeln('not origin');

while P.X < 10 do
  Inc(P.X);

for P.Y := 1 to 3 do
  writeln(P.Y);
```

## Routines

Procedures do not return a value. Functions assign their return value through
`Result`:

```pascal
function Twice(N: Integer): Integer;
begin
  Result := N * 2;
end;
```

Parameters can be passed by value, `const`, `var`, or `out`, depending on the
routine contract.

## Units

Reusable code lives in units and is imported with `uses`:

```pascal
program app;
uses sysutils;
begin
  writeln(IntToStr(123));
end.
```

The `pxx` wrapper created by `install.sh` adds the bundled library roots, so
project units can usually be found without extra flags.

## Next

- [Types](./types.md)
- [PXX dialect](./dialect.md)
