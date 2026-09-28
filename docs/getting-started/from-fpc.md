---
title: Coming from Free Pascal
order: 23
---

# Coming from Free Pascal

If you write Free Pascal, you already write the language PXX compiles. PXX aims
at the Object Pascal that FPC accepts, in `objfpc` and Delphi mode. It does
**not** reproduce FPC's world around the language: its RTL and packages, its
command line, and its unit and object files. This page lists what carries over
unchanged, what the mode lines do, where the two compilers give different
answers, and how to build a small FPC program.

**What was checked.** Every program on this page was compiled with pin v447
(compiler sha256 `fad87004e4e8`) and with FPC 3.2.2 (`fpc -O1`) on x86-64
Linux on 2026-09-28. Both binaries were run. Where the output is the same, the
page shows it once; where it differs, it shows both.

## What compiles unchanged

Ordinary FPC programs are the best fit: records, arrays, classes and
inheritance, properties, generics, exceptions, `for ... in`, units, and the
common parts of `SysUtils` and `Classes`. This program uses all of them and
prints the same thing under both compilers:

```pascal
program shapes;
{$mode objfpc}{$H+}
uses SysUtils, Classes;

type
  EEmptyStack = class(Exception);

  TShape = class
  private
    FName: string;
  public
    constructor Create(const AName: string);
    function Area: Double; virtual; abstract;
    property Name: string read FName;
  end;

  TCircle = class(TShape)
  private
    FR: Double;
  public
    constructor Create(AR: Double);
    function Area: Double; override;
  end;

  TRectangle = class(TShape)
  private
    FW, FH: Double;
  public
    constructor Create(AW, AH: Double);
    function Area: Double; override;
  end;

  generic TStack<T> = class
  private
    FItems: array of T;
  public
    procedure Push(const V: T);
    function Pop: T;
    function Count: Integer;
  end;

  TIntStack = specialize TStack<Integer>;

constructor TShape.Create(const AName: string);
begin
  FName := AName;
end;

constructor TCircle.Create(AR: Double);
begin
  inherited Create('circle');
  FR := AR;
end;

function TCircle.Area: Double;
begin
  Result := Pi * FR * FR;
end;

constructor TRectangle.Create(AW, AH: Double);
begin
  inherited Create('rectangle');
  FW := AW; FH := AH;
end;

function TRectangle.Area: Double;
begin
  Result := FW * FH;
end;

procedure TStack.Push(const V: T);
begin
  SetLength(FItems, Length(FItems) + 1);
  FItems[High(FItems)] := V;
end;

function TStack.Pop: T;
begin
  if Length(FItems) = 0 then
    raise EEmptyStack.Create('pop from an empty stack');
  Result := FItems[High(FItems)];
  SetLength(FItems, Length(FItems) - 1);
end;

function TStack.Count: Integer;
begin
  Result := Length(FItems);
end;

var
  all: array of TShape;
  s: TShape;
  names: TStringList;
  st: TIntStack;
  i: Integer;
begin
  SetLength(all, 3);
  all[0] := TCircle.Create(1.5);
  all[1] := TRectangle.Create(2, 3.5);
  all[2] := TCircle.Create(0.5);
  for s in all do
    WriteLn(Format('%-10s %8.3f', [s.Name, s.Area]));

  names := TStringList.Create;
  try
    names.CommaText := 'pear,apple,fig,banana';
    names.Sort;
    WriteLn(names.CommaText, ' (', names.Count, ')');
    WriteLn(UpperCase(names[0]), ' ', Pos('an', names[1]), ' ', Copy(names[3], 1, 2));
  finally
    names.Free;
  end;

  st := TIntStack.Create;
  for i := 1 to 3 do st.Push(i * i);
  while st.Count > 0 do Write(st.Pop, ' ');
  WriteLn;
  try
    st.Pop;
  except
    on E: EEmptyStack do WriteLn('caught ', E.ClassName, ': ', E.Message);
  end;
  st.Free;
  for s in all do s.Free;
end.
```

```text
circle        7.069
rectangle     7.000
circle        0.785
apple,banana,fig,pear (4)
APPLE 2 pe
9 4 1
caught EEmptyStack: pop from an empty stack
```

On a larger scale, PXX runs a curated 550 programs of FPC 3.2.2's own test
suite (`tools/run_pascal_conformance.sh`). With pin v441, 427 pass and 0
fail; 50 do not apply here, and 73 are skipped, each with a written reason
(see [the examples showcase](../examples/index.md)).

## Mode lines

PXX has one dialect. `{$mode objfpc}`, `{$mode fpc}`, `{$mode tp}`,
`{$mode delphiunicode}` and `-Mobjfpc` are accepted and change nothing.
`{$mode delphi}` changes two things:

- nested `{ }` comments are off, as in Delphi;
- a routine can be assigned to a procedural variable without `@`.

Delphi's generic syntax, with no `generic` or `specialize` keyword, is accepted
in that mode as in FPC:

```pascal
program delphimode;
{$mode delphi}
type
  TIntFunc = function(x: Integer): Integer;

  TPair<T> = record
    A, B: T;
    function Swapped: TPair<T>;
  end;

function Twice(x: Integer): Integer;
begin
  Result := 2 * x;
end;

function TPair<T>.Swapped: TPair<T>;
begin
  Result.A := B;
  Result.B := A;
end;

var
  f: TIntFunc;
  p: TPair<Integer>;
begin
  f := Twice;          { no @ in delphi mode }
  p.A := 1; p.B := 2;
  p := p.Swapped;
  WriteLn(f(21), ' ', p.A, ' ', p.B);
end.
```

It prints `42 2 1` under both. `{$mode iso}` and `{$mode extendedpascal}` give
a warning, and `{$mode macpas}` is an error. The whole model, including the
strictness switches, is on [Compiler modes](../reference/modes.md).

To tell the two compilers apart in source, test `PXX`. PXX does not define
`FPC`:

```pascal
program ifdefs;
begin
{$ifdef PXX}
  WriteLn('built by pxx');
{$endif}
{$ifdef FPC}
  WriteLn('built by fpc');
{$endif}
end.
```

## What gives a different answer

These are deliberate. Each was decided rather than left as a bug, and each
compiles under both compilers. The outputs are from the programs as shown.

**Shifts on a 32-bit `Integer` happen at full width.** FPC masks the shift
count to 5 bits and truncates to 32 bits; PXX does not lose bits.
`--strict-fpc` gives FPC's answers:

```pascal
program shifts;
{$mode objfpc}
var a, b: Integer;
begin
  a := -8;
  WriteLn(a shr 1);
  a := 8; b := 40;
  WriteLn(a shl b);
  a := 1;
  WriteLn(a shl 31);
end.
```

| | FPC 3.2.2 | PXX | PXX `--strict-fpc` |
| --- | --- | --- | --- |
| `a shr 1`, a = -8 | 2147483644 | 9223372036854775804 | 2147483644 |
| `a shl b`, 8 and 40 | 2048 | 8796093022208 | 2048 |
| `a shl 31`, a = 1 | -2147483648 | 2147483648 | -2147483648 |

**`Assert` is on by default.** FPC ignores `Assert` unless you build with
`-Sa`; PXX checks it. With `fpc -Sa` both print `assert raised`:

```pascal
program asserts;
{$mode objfpc}
uses SysUtils;
begin
  try
    Assert(1 + 1 = 3, 'arithmetic is broken');
    WriteLn('assert skipped');
  except
    on E: EAssertionFailed do WriteLn('assert raised');
  end;
end.
```

FPC prints `assert skipped`, and PXX prints `assert raised`.

**A pointer difference always counts elements.** When one side is an untyped
`Pointer`, FPC counts bytes. Cast to say which you mean, and both agree:

```pascal
program ptrdiff;
{$mode objfpc}
type PInt = ^Integer;
var a: array[0..7] of Integer; p, p0: PInt; u: Pointer;
begin
  p0 := @a[0]; p := @a[2]; u := @a[0];
  WriteLn(p - p0);                    { 2 in both }
  WriteLn(p - u);                     { FPC 8 (bytes), PXX 2 (elements) }
  WriteLn(p - PInt(u));               { 2 in both }
  WriteLn(PtrUInt(p) - PtrUInt(u));   { 8 in both }
end.
```

**`Null` and `Unassigned` are one value.** A `Variant` holding either is empty,
so `VarIsNull` and `VarIsEmpty` are both true for both, and neither raises
when printed:

```pascal
program variantnull;
{$mode objfpc}
uses Variants;
var v: Variant;
begin
  v := Null;
  WriteLn(VarType(v), ' ', VarIsNull(v), ' ', VarIsEmpty(v));
  v := Unassigned;
  WriteLn(VarType(v), ' ', VarIsNull(v), ' ', VarIsEmpty(v));
end.
```

| | FPC 3.2.2 | PXX |
| --- | --- | --- |
| after `v := Null` | `1 TRUE FALSE` | `0 TRUE TRUE` |
| after `v := Unassigned` | `0 FALSE TRUE` | `0 TRUE TRUE` |

A program that uses `VarIsNull` to tell a database NULL from an unset variant
cannot do so here.

**Nested comments in `{$mode tp}`.** FPC 3.2.2 nests `{ }` comments in its
default and `objfpc` modes, with a "Comment level 2 found" warning, and does
not nest them in `delphi` and `tp` mode. PXX nests them in every mode but
`delphi`, so `{ a {b} c }` compiles under PXX in `tp` mode and is a syntax
error under FPC there.

**`Random` gives a different sequence for the same seed.** PXX has its own
random-number generator, not FPC's Mersenne Twister, so a program that relies
on the numbers a seed produces under FPC gets others:

```pascal
program rnd;
var i: Integer;
begin
  RandSeed := 42;
  for i := 1 to 5 do Write(Random(100), ' ');
  WriteLn;
end.
```

FPC prints `37 79 95 18 73`, and PXX prints `20 80 2 66 15`.

**On the ESP32, `Real` is `Single`.** FPC makes `Real` a `Double` everywhere;
PXX uses the target's native float width. See
[Types](../language/types.md#real-is-the-targets-native-float).

The full list, with the reasoning for each, is kept for the compiler's
developers in `devdocs/dev/pascal-dialect-divergences.md`. Problems that are
not deliberate are on [Known issues](../reference/known-issues.md).

## The RTL is PXX's own

PXX ships its own units under FPC's names: `SysUtils`, `Classes`, `Math`,
`StrUtils`, `DateUtils`, `Variants`, `TypInfo`, `Contnrs`, `SyncObjs`,
`BaseUnix` and `Unix`, among others. They are written from scratch and cover
the common part of FPC's, not all of it. Some units FPC programs often use
**do not exist**: `fgl`, `Generics.Collections`, `Crt`, `Dos`, `IniFiles`,
`Process`, `fpjson`, `jsonparser`, `RegExpr` and `StreamIO`. A missing unit
stops the compile at the `uses` line:

```text
pascal26:3: error: uses: unit source not found: fgl
```

Within the units that exist, a few common routines are missing. Checked
2026-09-28 with pin v447, against 28 routines FPC programs use often:
`FormatFloat` is not in `SysUtils`, and `TStringList` has no `LoadFromFile`
or `SaveToFile`. The other 25 compiled, among them `Format`, `FloatToStrF`,
`StrToIntDef`, `StringReplace`, `FileExists`, `ExtractFileName`, `Now`,
`FormatDateTime`, `SplitString` and `Power`. Use `Format` for
`FormatFloat`. For a string list, go through a stream, which both compilers
accept:

```pascal
program slfile;
{$mode objfpc}{$H+}
uses SysUtils, Classes;
var sl: TStringList; fs: TFileStream;
begin
  sl := TStringList.Create;
  sl.Add('first');
  sl.Add('second');
  fs := TFileStream.Create('list.txt', fmCreate);
  try
    sl.SaveToStream(fs);      { instead of sl.SaveToFile('list.txt') }
  finally
    fs.Free;
  end;
  sl.Clear;
  fs := TFileStream.Create('list.txt', fmOpenRead);
  try
    sl.LoadFromStream(fs);    { instead of sl.LoadFromFile('list.txt') }
  finally
    fs.Free;
  end;
  WriteLn(sl.Count, ' lines, last: ', sl[sl.Count - 1]);
  sl.Free;
end.
```

It prints `2 lines, last: second` under both.

## Building a small FPC program

A program with one unit in `src/`:

```pascal
unit geometry;
{$mode objfpc}{$H+}
interface

type
  TPoint2 = record
    X, Y: Double;
  end;

function Distance(const A, B: TPoint2): Double;
function Describe(const P: TPoint2): string;

implementation

uses SysUtils, Math;

function Distance(const A, B: TPoint2): Double;
begin
  Result := Hypot(B.X - A.X, B.Y - A.Y);
end;

function Describe(const P: TPoint2): string;
begin
  Result := Format('(%.1f, %.1f)', [P.X, P.Y]);
end;

end.
```

```pascal
program main;
{$mode objfpc}{$H+}
uses SysUtils, geometry;
var a, b: TPoint2;
begin
  a.X := 1; a.Y := 2;
  b.X := 4; b.Y := 6;
  WriteLn(Describe(a), ' to ', Describe(b), ' is ', Format('%.3f', [Distance(a, b)]));
end.
```

The two command lines side by side:

```sh
fpc -Fusrc main.pas              # FPC: writes ./main, plus .o and .ppu files
./pxx -Fusrc main.pas main       # PXX: the output name is the second argument
```

Both print `(1.0, 2.0) to (4.0, 6.0) is 5.000`. PXX writes one static
executable and no `.o` or `.ppu` files; it compiles the units again on every
build. `-Fu` and `-Fi` work as in FPC, but most other FPC switches do not:
the command line is PXX's own. See [Command line](../reference/cli.md).

For library code that chooses a branch by asking `{$ifdef FPC}`, `--mimic-fpc`
turns on a curated set of FPC's defines, `FPC` among them: built with it, the
`ifdefs` program above prints both lines. Use it only for such code; see
[FPC compatibility](../language/fpc-compatibility.md).

## Next

- [FPC compatibility](../language/fpc-compatibility.md)
- [PXX dialect](../language/dialect.md)
- [Compiler modes](../reference/modes.md)
- [Known issues](../reference/known-issues.md)
