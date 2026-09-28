---
title: FPC RTL coverage
order: 92
---

# FPC RTL coverage

This page lists the 150 Free Pascal library routines and classes that FPC's
own code uses most, and says for each whether PXX has it. It was measured on
2026-09-28 with **pin v447** (commit `60c5ec9dc0`, compiler sha256
`fad87004e4e8…`), on x86-64 Linux, against **fpc 3.2.2**.

Of the 150:

| Result | Count |
|---|---|
| present: compiles and prints the same as FPC | 124 |
| missing: the name is undefined or its type is unknown | 14 |
| missing overload or member: the name exists, but a common form of it does not | 7 |
| present, different: compiles, but prints or exits differently | 5 |

"Present" means one call gave the same output. It does not mean every
overload, option or edge case behaves the same.

## How the list was made

The candidates are every routine and class declared in the interface of FPC
3.2.2's `System`, `SysUtils`, `Classes`, `StrUtils` and `Math` units, plus the
compiler intrinsics such as `WriteLn`, `Inc` and `SizeOf`. That is 938 names.
Each name was counted as a whole word, ignoring case, in the 4,894 Pascal
sources under `/usr/share/fpcsrc/3.2.2/packages` (FPC's own packages; Lazarus
was not installed). The list is ranked by how many files use the name, and
the top 150 are kept. Three internal names (`get_frame`, `StackTop`, `SPtr`)
were left out.

A count is a count of words, not of calls. Common words such as `Read`,
`Write`, `Error`, `Time`, `Date`, `Point` and `Sec` are also method, field or
variable names, so their counts are too high. The ranking is good enough to
choose the 150, but it is not an exact popularity order.

Each name got one probe program:

```pascal
program probe;
{$mode objfpc}{$H+}
uses SysUtils, Classes, StrUtils, Math;
var s: string;
begin
  s := 'abcdef'; Delete(s, 2, 3); writeln(s);
end.
```

Each probe was built with `fpc -O2` and with the pinned PXX. Both programs
were run, and their standard output and exit codes were compared. A probe
that FPC refused was fixed until FPC accepted it. When a probe failed in PXX,
it was split into smaller probes, one call each, to find the form that fails.

## Missing, ranked by use

"Files" is the number of FPC package source files that use the name.

| Rank | Name | Unit | Files | What is missing |
|---|---|---|---|---|
| 14 | `Copy` | System | 390 | `Copy(s, index)` (two arguments) is refused: "no overload of Copy matches". The three-argument form works. |
| 18 | `Pos` | System | 352 | `Pos(sub, s, offset)` (three arguments) is refused. The two-argument form works. |
| 39 | `Rect` | Classes | 197 | `TRect` is an unknown type, so `Rect` cannot be used. |
| 42 | `Ptr` | System | 184 | Undefined. FPC keeps it for 16-bit code: `Ptr(seg, ofs)`. |
| 50 | `Point` | Classes | 150 | `TPoint` is an unknown type. |
| 57 | `Addr` | System | 111 | Undefined; use `@`. |
| 66 | `Bounds` | Classes | 98 | `TRect` is an unknown type. |
| 67 | `TGuid` | System | 97 | The `TGuid` record works; `GUIDToString` is undefined. |
| 68 | `TList` | Classes | 97 | `Add`, `Count` and `Items` work; `Pack` is not a member. |
| 73 | `TypeInfo` | System | 89 | `TypeInfo(Integer)` works; `PTypeInfo(...)^.Name` is not a member. |
| 81 | `UpCase` | System | 80 | `UpCase(char)` works; `UpCase(string)` is refused. |
| 85 | `Align` | System | 73 | Undefined. |
| 86 | `Random` | System | 72 | `Random(n)` works; `Random` with no argument (a Double in [0,1)) is undefined. |
| 91 | `TCollection` | Classes | 69 | Unknown type. |
| 93 | `Space` | System | 67 | Undefined. |
| 102 | `TCollectionItem` | Classes | 55 | Unknown type (with `TCollection`). |
| 116 | `NewStr` | SysUtils | 42 | `PString` is an unknown type, so `NewStr` cannot be used. |
| 134 | `DisposeStr` | SysUtils | 28 | `PString` is an unknown type. |
| 142 | `Sum` | Math | 25 | Undefined in `Math`. |
| 146 | `SwapEndian` | System | 23 | Undefined. |
| 150 | `MaxValue` | Math | 22 | Undefined in `Math`. |

The earlier 28-routine check found three more that are outside this top 150:
`FormatFloat` (20 files), and `TStringList.LoadFromFile` and `SaveToFile`.
They are covered in [Coming from Free Pascal](../getting-started/from-fpc.md).

## Present, but different

| Rank | Name | Unit | Files | Difference |
|---|---|---|---|---|
| 8 | `Error` | System | 701 | `Error(reRangeError)` raises `ERangeError` (unhandled, exit 217). FPC stops with "Runtime error 201", exit 201. |
| 112 | `TInterfacedObject` | System | 47 | Works as a class and through a declared interface or `IUnknown`. Assigning it to `IInterface` is refused: "class does not implement the interface". Without `SysUtils` it is undefined; FPC has it in `System`. |
| 120 | `UTF8Decode` | System | 35 | `UTF8Decode('h'#$C3#$A9)` has length 3, not 2: the bytes are not decoded. ASCII input is the same. |
| 136 | `RunError` | System | 27 | Exit code 204 as in FPC, but "Runtime error 204" goes to standard output; FPC writes it to standard error. |
| 139 | `Power` | Math | 26 | `Power(2, 10)` gives an integer (`1024` under `:0:1`), FPC a float (`1024.0`). `Power(2.0, 10.0)` is the same. |

## A compiler gap found along the way

Passing one character of a string to a `var` parameter crashes when that
string still shares a literal. The same code in FPC prints `ayc`:

```pascal
program varchar;
{$mode objfpc}{$H+}
procedure SetC(var c: char); begin c := 'y'; end;
var s: string;
begin
  s := 'abc';
  SetC(s[2]);        { PXX v447: segmentation fault }
  writeln(s);
end.
```

Assigning `s[2] := 'y'` directly works, and so does calling `UniqueString(s)`
first. `Move(src[1], dst[2], 3)` into such a string crashes the same way.

## All 150

| Rank | Name | Unit | Files | Result |
|---|---|---|---|---|
| 1 | `Exit` | System | 1058 | present |
| 2 | `Length` | System | 950 | present |
| 3 | `Inc` | System | 916 | present |
| 4 | `Read` | System | 851 | present |
| 5 | `Write` | System | 808 | present |
| 6 | `Assigned` | System | 735 | present |
| 7 | `SizeOf` | System | 705 | present |
| 8 | `Error` | System | 701 | present, different |
| 9 | `WriteLn` | System | 659 | present |
| 10 | `Format` | SysUtils | 600 | present |
| 11 | `Dec` | System | 512 | present |
| 12 | `SetLength` | System | 433 | present |
| 13 | `Delete` | System | 430 | present |
| 14 | `Copy` | System | 390 | missing overload or member |
| 15 | `FreeAndNil` | SysUtils | 380 | present |
| 16 | `TObject` | System | 375 | present |
| 17 | `Break` | System | 366 | present |
| 18 | `Pos` | System | 352 | missing overload or member |
| 19 | `Ord` | System | 350 | present |
| 20 | `Close` | System | 332 | present |
| 21 | `Str` | System | 323 | present |
| 22 | `TComponent` | Classes | 315 | present |
| 23 | `IntToStr` | SysUtils | 304 | present |
| 24 | `High` | System | 301 | present |
| 25 | `Move` | System | 288 | present |
| 26 | `TStream` | Classes | 282 | present |
| 27 | `Default` | System | 282 | present |
| 28 | `Assign` | System | 280 | present |
| 29 | `TStringList` | Classes | 264 | present |
| 30 | `New` | System | 257 | present |
| 31 | `Freemem` | System | 254 | present |
| 32 | `Getmem` | System | 253 | present |
| 33 | `FillChar` | System | 245 | present |
| 34 | `Insert` | System | 236 | present |
| 35 | `TStrings` | Classes | 224 | present |
| 36 | `Time` | SysUtils | 223 | present |
| 37 | `Halt` | System | 220 | present |
| 38 | `Val` | System | 201 | present |
| 39 | `Rect` | Classes | 197 | missing |
| 40 | `ParamStr` | System | 196 | present |
| 41 | `Reset` | System | 187 | present |
| 42 | `Ptr` | System | 184 | missing |
| 43 | `Low` | System | 183 | present |
| 44 | `Int` | System | 182 | present |
| 45 | `Pred` | System | 162 | present |
| 46 | `Continue` | System | 154 | present |
| 47 | `Dispose` | System | 152 | present |
| 48 | `Date` | SysUtils | 151 | present |
| 49 | `EOF` | System | 151 | present |
| 50 | `Point` | Classes | 150 | missing |
| 51 | `Max` | Math | 146 | present |
| 52 | `Min` | Math | 142 | present |
| 53 | `TFileStream` | Classes | 127 | present |
| 54 | `LowerCase` | System | 127 | present |
| 55 | `FileExists` | SysUtils | 122 | present |
| 56 | `ParamCount` | System | 113 | present |
| 57 | `Addr` | System | 111 | missing |
| 58 | `Round` | System | 111 | present |
| 59 | `Trim` | SysUtils | 107 | present |
| 60 | `Include` | System | 105 | present |
| 61 | `Seek` | System | 105 | present |
| 62 | `CompareText` | SysUtils | 102 | present |
| 63 | `Now` | SysUtils | 102 | present |
| 64 | `Initialize` | System | 102 | present |
| 65 | `ReadLn` | System | 100 | present |
| 66 | `Bounds` | Classes | 98 | missing |
| 67 | `TGuid` | System | 97 | missing overload or member |
| 68 | `TList` | Classes | 97 | missing overload or member |
| 69 | `TMemoryStream` | Classes | 96 | present |
| 70 | `Chr` | System | 95 | present |
| 71 | `Succ` | System | 94 | present |
| 72 | `StrLen` | System | 91 | present |
| 73 | `TypeInfo` | System | 89 | missing overload or member |
| 74 | `Append` | System | 86 | present |
| 75 | `Flush` | System | 86 | present |
| 76 | `Rewrite` | System | 85 | present |
| 77 | `TPersistent` | Classes | 84 | present |
| 78 | `TFPList` | Classes | 83 | present |
| 79 | `Abs` | System | 81 | present |
| 80 | `Assert` | System | 80 | present |
| 81 | `UpCase` | System | 80 | missing overload or member |
| 82 | `StrPas` | System | 78 | present |
| 83 | `StrToIntDef` | SysUtils | 75 | present |
| 84 | `Trunc` | System | 73 | present |
| 85 | `Align` | System | 73 | missing |
| 86 | `Random` | System | 72 | missing overload or member |
| 87 | `TStringStream` | Classes | 72 | present |
| 88 | `StrToInt` | SysUtils | 72 | present |
| 89 | `UpperCase` | SysUtils | 71 | present |
| 90 | `ExtractFileName` | SysUtils | 71 | present |
| 91 | `TCollection` | Classes | 69 | missing |
| 92 | `Hi` | System | 68 | present |
| 93 | `Space` | System | 67 | missing |
| 94 | `ExtractFilePath` | SysUtils | 67 | present |
| 95 | `HexStr` | System | 64 | present |
| 96 | `Sin` | System | 64 | present |
| 97 | `Pi` | System | 62 | present |
| 98 | `StringReplace` | SysUtils | 60 | present |
| 99 | `IOResult` | System | 59 | present |
| 100 | `SetString` | System | 58 | present |
| 101 | `FormatDateTime` | SysUtils | 58 | present |
| 102 | `TCollectionItem` | Classes | 55 | missing |
| 103 | `Cos` | System | 54 | present |
| 104 | `SameText` | SysUtils | 54 | present |
| 105 | `Sleep` | SysUtils | 54 | present |
| 106 | `Lo` | System | 51 | present |
| 107 | `ChangeFileExt` | SysUtils | 51 | present |
| 108 | `StringOfChar` | System | 49 | present |
| 109 | `IncludeTrailingPathDelimiter` | SysUtils | 47 | present |
| 110 | `Sqrt` | System | 47 | present |
| 111 | `DeleteFile` | SysUtils | 47 | present |
| 112 | `TInterfacedObject` | System | 47 | present, different |
| 113 | `Exp` | System | 44 | present |
| 114 | `Sqr` | System | 44 | present |
| 115 | `Sec` | Math | 44 | present |
| 116 | `NewStr` | SysUtils | 42 | missing |
| 117 | `Exclude` | System | 39 | present |
| 118 | `BoolToStr` | SysUtils | 37 | present |
| 119 | `strcomp` | SysUtils | 37 | present |
| 120 | `UTF8Decode` | System | 35 | present, different |
| 121 | `UTF8Encode` | System | 35 | present |
| 122 | `ReAllocMem` | System | 34 | present |
| 123 | `FindNext` | SysUtils | 34 | present |
| 124 | `EncodeDate` | SysUtils | 32 | present |
| 125 | `FloatToStr` | SysUtils | 32 | present |
| 126 | `FindFirst` | SysUtils | 32 | present |
| 127 | `FileSize` | System | 31 | present |
| 128 | `GetEnvironmentVariable` | SysUtils | 31 | present |
| 129 | `AllocMem` | System | 31 | present |
| 130 | `ExtractFileExt` | SysUtils | 31 | present |
| 131 | `Ln` | System | 29 | present |
| 132 | `ExpandFileName` | SysUtils | 29 | present |
| 133 | `Randomize` | System | 28 | present |
| 134 | `DisposeStr` | SysUtils | 28 | missing |
| 135 | `BlockRead` | System | 28 | present |
| 136 | `RunError` | System | 27 | present, different |
| 137 | `EConvertError` | SysUtils | 27 | present |
| 138 | `FindClose` | SysUtils | 27 | present |
| 139 | `Power` | Math | 26 | present, different |
| 140 | `EncodeTime` | SysUtils | 26 | present |
| 141 | `Erase` | System | 26 | present |
| 142 | `Sum` | Math | 25 | missing |
| 143 | `DateTimeToStr` | SysUtils | 25 | present |
| 144 | `StrDispose` | SysUtils | 24 | present |
| 145 | `Odd` | System | 24 | present |
| 146 | `SwapEndian` | System | 23 | missing |
| 147 | `strcopy` | SysUtils | 23 | present |
| 148 | `DecodeTime` | SysUtils | 23 | present |
| 149 | `Sign` | Math | 22 | present |
| 150 | `MaxValue` | Math | 22 | missing |
