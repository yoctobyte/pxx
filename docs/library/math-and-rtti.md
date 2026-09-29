---
title: Complex numbers, vectors, RTTI
order: 52
---

# Complex numbers, vectors and RTTI

Three Pascal units:

| Unit | What it does | Compared with |
| --- | --- | --- |
| [`ucomplex`](#ucomplex-complex-numbers) | Complex numbers, with FPC's `ucomplex` names | FPC 3.2.2's `ucomplex` |
| [`vecmath`](#vecmath-vectors-and-matrices) | 2-, 3- and 4-component vectors and 3x3 and 4x4 matrices, for geometry and graphics | Python, by hand |
| [`typinfo`](#typinfo-properties-by-name) | Reading and writing an object's published properties by name | FPC 3.2.2's `typinfo` |

Each example was built with pin v451 (compiler sha256 `d9b7226769cc`)
through `./pxx` on Linux x86-64 on 2026-09-29, and printed exactly what the
compared program printed.

## ucomplex: complex numbers

A `complex` is a record with `re` and `im`. Build one with `cinit(re, im)`.
The operators `+`, `-`, `*`, `/` and `=` work between two complex numbers,
and the functions have FPC's names: `cmod` (modulus), `carg` (argument),
`cong` (conjugate), `csqrt`, `cexp`, `cln`, `cpow`, `csin`, `ccos` and the
rest, and `cstr(z, width, decimals)` for text.

The roots of x² + 2x + 5 = 0:

```pascal
program cx_demo;
{$mode objfpc}
uses ucomplex;

{$ifdef FPC}
function cneg(z: complex): complex; begin cneg := -z; end;   { FPC spells it -z }
{$endif}

var
  a, b, c, d, r1, r2, check: complex;
begin
  a := cinit(1, 0); b := cinit(2, 0); c := cinit(5, 0);
  d := csqrt(b * b - cinit(4, 0) * a * c);
  r1 := (cneg(b) + d) / (cinit(2, 0) * a);
  r2 := (cneg(b) - d) / (cinit(2, 0) * a);
  writeln('root 1: ', cstr(r1, 0, 3));
  writeln('root 2: ', cstr(r2, 0, 3));
  check := r1 * r1 + b * r1 + c;
  writeln('check: ', cstr(check, 0, 3));
  writeln('|root 1| = ', cmod(r1):0:4);
  writeln('arg(root 1) = ', carg(r1):0:4);
  writeln('conjugates: ', r1 = cong(r2));
  writeln('exp(i*pi) = ', cstr(cexp(cinit(0, pi)), 0, 3));
end.
```

```text
root 1: -1.000+2.000i
root 2: -1.000-2.000i
check: 0.000
|root 1| = 2.2361
arg(root 1) = 2.0344
conjugates: TRUE
exp(i*pi) = -1.000+0.000i
```

FPC 3.2.2 prints the same seven lines. Where PXX differs from FPC's unit,
measured with v451:

- **Negate with `cneg(z)`, not `-z`.** With v451, `w := -z` compiles but
  the program crashes when it runs (see
  [Known issues](../reference/known-issues.md#stops-at-run-time)). Fixed
  after v451 (`f499d25ded`, in no pin yet): the compiler built there
  (`81c16b5e3461`) gives `-z` the same answer as `cneg(z)` and as FPC,
  `-1.0-2.0i` for `cinit(1, 2)`. FPC's unit has no `cneg`, which is why the
  example defines one for FPC.
- **A real number works on the right of an operator but not on the left.**
  `z + 1.0`, `z - 1.0`, `z * 2.0` and `z / 2.0` give FPC's results;
  `1.0 + z` and `2.0 * z` stop the build ("no operator overload found for
  record operands"). Write `cinit(2, 0) * z`, or use `cmulr` and the other
  function forms.
- **No `**`.** Use `cpow(z1, z2)` or `cpowr(z, r)`.
- **No assignment from a real:** `z := 2.0` is refused. Write `cinit(2, 0)`.
- `z <> w` works.

The functions compute with PXX's own `math` unit, not the C library.

## vecmath: vectors and matrices

`TVec2`, `TVec3` and `TVec4` hold `x`, `y`, `z` and `w` as doubles, and
`Vec3(x, y, z)` builds one. Vectors add and subtract, and multiply or divide
by a number on the right (`v * 0.5`). `Dot`, `Cross`, `Norm`, `NormSq`,
`Normalize`, `Lerp` and `VMul` (component by component) work on each size.
`TMat3` and `TMat4` are row-major (`m[r * 4 + c]`), multiply with `*`, and
come from `Mat4Identity`, `Mat4Translate`, `Mat4Scale` and
`Mat4RotateX/Y/Z` (angles in radians). `MulMV(m, v)` applies a matrix to a
vector, and `Transpose` and `Det` do what their names say. This unit is
PXX's own; FPC has no unit of this name.

```pascal
program vec_demo;
uses vecmath;

procedure Show(const name: string; const v: TVec3);
begin
  writeln(name, ' = (', v.x:0:3, ', ', v.y:0:3, ', ', v.z:0:3, ')');
end;

var
  a, b, c, n: TVec3;
  m: TMat4;
  p: TVec4;
begin
  a := Vec3(0, 0, 0);
  b := Vec3(4, 0, 0);
  c := Vec3(0, 3, 0);
  n := Cross(b - a, c - a);
  Show('cross', n);
  writeln('area = ', Norm(n) / 2:0:3);
  Show('unit normal', Normalize(n));
  writeln('dot(ab, ac) = ', Dot(b - a, c - a):0:3);
  Show('midpoint of bc', Lerp(b, c, 0.5));
  Show('ab * 0.25', (b - a) * 0.25);

  { turn 90 degrees about z, then move 10 along x: translate * rotate }
  m := Mat4Translate(10, 0, 0) * Mat4RotateZ(Pi / 2);
  p := MulMV(m, Vec4(b.x, b.y, b.z, 1));
  writeln('b moved = (', p.x:0:3, ', ', p.y:0:3, ', ', p.z:0:3, ')');
  writeln('det(rotation) = ', Det(Mat4RotateZ(Pi / 2)):0:3);
end.
```

```text
cross = (0.000, 0.000, 12.000)
area = 6.000
unit normal = (0.000, 0.000, 1.000)
dot(ab, ac) = 0.000
midpoint of bc = (2.000, 1.500, 0.000)
ab * 0.25 = (1.000, 0.000, 0.000)
b moved = (10.000, 4.000, 0.000)
det(rotation) = 1.000
```

The same steps written out in Python give the same eight lines. As with
`ucomplex`, a number goes on the right (`v * 0.25`; `0.25 * v` is refused),
and with v451 `-v` compiles but crashes: write `v * -1.0`. After v451
(`f499d25ded`, in no pin yet), `-v` stops the build instead, with FPC's
message for a type that has no unary minus: `Operator is not overloaded: -
"TVec3"`.

## typinfo: properties by name

`typinfo` reads and writes the published properties of an object by name,
the way a settings loader or a form designer does. The routines have FPC's
names and take the object and the property name: `GetStrProp`/`SetStrProp`,
`GetOrdProp`/`SetOrdProp`, `GetInt64Prop`, `GetFloatProp`/`SetFloatProp`,
`GetEnumProp`/`SetEnumProp` (the value as its name), `GetSetProp`,
`GetObjectProp`, `GetMethodProp`, `IsPublishedProp` and `PropType`.
`GetEnumName(TypeInfo(T), n)` and `GetEnumValue(TypeInfo(T), 'name')` work
as in FPC.

```pascal
program rtti_demo;
{$mode objfpc}{$M+}
uses typinfo;

type
  TColour = (clRed, clGreen, clBlue);

  TShape = class
  private
    FName: string;
    FSides: Integer;
    FColour: TColour;
    FScale: Double;
  published
    property Name: string read FName write FName;
    property Sides: Integer read FSides write FSides;
    property Colour: TColour read FColour write FColour;
    property Scale: Double read FScale write FScale;
  end;

var
  s: TShape;
begin
  s := TShape.Create;
  SetStrProp(s, 'Name', 'box');
  SetOrdProp(s, 'Sides', 4);
  SetEnumProp(s, 'Colour', 'clBlue');
  SetFloatProp(s, 'Scale', 1.5);
  writeln('Name = ', GetStrProp(s, 'Name'));
  writeln('Sides = ', GetOrdProp(s, 'Sides'));
  writeln('Colour = ', GetEnumProp(s, 'Colour'));
  writeln('Scale = ', GetFloatProp(s, 'Scale'):0:2);
  writeln('field check: ', s.Sides, ' ', Ord(s.Colour));
  writeln('Sides is published: ', IsPublishedProp(s, 'Sides'));
  writeln('Weight is published: ', IsPublishedProp(s, 'Weight'));
  writeln('Sides is an integer: ', PropType(s, 'Sides') = tkInteger);
  s.Free;
end.
```

```text
Name = box
Sides = 4
Colour = clBlue
Scale = 1.50
field check: 4 2
Sides is published: TRUE
Weight is published: FALSE
Sides is an integer: TRUE
```

FPC 3.2.2 prints the same eight lines.

**Listing the properties is written differently.** In FPC,
`GetPropList(obj, list)` allocates the list for you (`list: PPropList` is an
`out` parameter) and each entry has a `Name` field. In PXX you pass a list
you own, and the name is behind `NamePtr`:

```pascal
var list: TPropList; n, i: Integer;
...
n := GetPropList(s, @list);
for i := 0 to n - 1 do writeln(list[i]^.NamePtr^);
```

For `TShape` it prints `Name`, `Sides`, `Colour` and `Scale`, the same
names in the same order as FPC's form. The FPC form does not compile in PXX
("`Name`: no such member").

The streaming of `.lfm` form files in the [PCL](./pcl.md) is built on this
unit.
