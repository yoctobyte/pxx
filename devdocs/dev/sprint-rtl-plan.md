# Sprint plan: the FPC RTL gaps (2026-09-29)

This is the work list for the Pascal library sprint. It comes from the census
in [FPC RTL coverage](../../docs/reference/fpc-rtl-coverage.md). That census
was measured on 2026-09-28 with pin v447 (commit `60c5ec9dc0`, sha256
`fad87004e4e8…`) against fpc 3.2.2, on x86-64. The FPC semantics below were
read from `/usr/share/fpcsrc/3.2.2`, and the file named is where that source
lives. The pxx locations were read at master `8a008f44f9`.

**Files** is the census count: how many of the 4,894 FPC package sources use
the name. It counts words, so a common word (`Ptr`, `Random`) is counted too
high; where a narrower count helps, it is given too.

**Size**: S is under an hour, with one file and one test. M is half a day, or
has a collision or layout constraint to work around. L is a day or more.

Each item has an **accept** line: the census probe to run with the rebuilt
compiler, and the output fpc 3.2.2 gave for it on 2026-09-28. The
`GUIDToString`, `StringToGUID` and `Addr`-under-`{$T+}` claims were also run
with fpc 3.2.2. Every probe starts with:

```pascal
{$mode objfpc}{$H+}
uses SysUtils, Classes, StrUtils, Math;
```

## Already routed, not in this plan

- **franks-a3:** `Copy(s, index)`, `Pos(sub, s, offset)`, `UpCase(string)`,
  `Space`, `Power(int, int)`, and the crash when a string element is passed
  to a `var` parameter.
- **frankd-a3:** `FormatFloat`, `TStringList.LoadFromFile` and `SaveToFile`,
  and the affinity syscall numbers.

## The plan, ranked by file count

| # | Item | Files | Goes in | Size |
|---|---|---|---|---|
| 1 | `Rect` / `Point` / `Bounds` in `Classes` | 197 / 150 / 98 | `lib/rtl/classes.pas` | S |
| 2 | `Ptr` | 184 (mostly the word as a variable) | `compiler/builtin/builtin.pas` | S |
| 3 | `Addr` | 111 | compiler intrinsic | S |
| 4 | `GUIDToString` | 97 (`TGuid`); 14 name the routine | `lib/rtl/sysutils.pas` | S |
| 5 | `TList.Pack`, `TFPList.Pack` | 97 (`TList`); 6 call `.Pack` | `lib/rtl/classes.pas` | S |
| 6 | `PTypeInfo^.Name` | 89 (`TypeInfo`); 61 name `PTypeInfo` | `lib/rtl/typinfo.pas` | M |
| 7 | `Align` | 73 | `compiler/builtin/builtin.pas` | S |
| 8 | `Random` with no argument | 72 (`Random`); about 2 call it bare | `compiler/builtin/builtin.pas` | S |
| 9 | `TCollection` / `TCollectionItem` | 69 / 55 | `lib/rtl/classes.pas` | L |
| 10 | `IInterface` declared twice | 47 (`TInterfacedObject`) | `lib/rtl/classes.pas` | S |
| 11 | `NewStr` / `DisposeStr` | 42 / 28 | `lib/rtl/sysutils.pas`, `lib/rtl/typinfo.pas` | M |
| 12 | `Sum` (and `SumInt`, `Mean`) | 25 | `lib/rtl/math.pas` | S |
| 13 | `SwapEndian` | 23 | `compiler/builtin/builtin.pas` | S |
| 14 | `MaxValue` / `MinValue` | 22 | `lib/rtl/math.pas` | S |

### 1. `Rect`, `Point`, `Bounds` in `Classes` (S)

**FPC:** `Classes` re-exports `TPoint = Types.TPoint` and
`TRect = Types.TRect`, and declares its own
`Point(AX, AY: Integer): TPoint`,
`Rect(ALeft, ATop, ARight, ABottom: Integer): TRect` and
`Bounds(ALeft, ATop, AWidth, AHeight: Integer): TRect` (classesh.inc:27, 2206).
`Bounds` gives `Right = ALeft + AWidth` and `Bottom = ATop + AHeight`.

**pxx:** all five already exist in `lib/rtl/types.pas`; `Classes` does not
pass them on. So a program that names only `Classes`, as FPC programs do,
gets "unknown type: TRect". I measured that a pxx unit can re-export
`TPoint = Types.TPoint` and declare its own `Point`. The program using it gave
FPC's output, including when it named both `Types` and that unit.

**Accept:** `r:=Rect(1,2,3,4); writeln(r.Left,r.Top,r.Right,r.Bottom);` gives
`1234`, and `r:=Bounds(1,2,10,20); writeln(r.Right,r.Bottom);` gives `1122`.

### 2. `Ptr` (S, low value)

**FPC:** `Ptr(sel, off: LongInt): Pointer` returns
`Pointer((sel shl 4) + off)` (system.inc:679). It is kept for 16-bit
code; on 32 and 64 bit it is plain arithmetic.

**Accept:** `writeln(PtrUInt(Ptr(0,16)));` gives `16`. The file count is
mostly `Ptr` used as a variable name, so this ranks high but is worth little.

### 3. `Addr` (S, compiler)

**FPC:** `Addr(x)` is `@x`, but the result is always an untyped `Pointer`,
even under `{$T+}` (typed `@`).

**Accept:** `i:=9; pi_:=Addr(i); writeln(pi_^);` gives `9`.

### 4. `GUIDToString` (S)

**FPC:** the result is 38 characters, with upper-case hex:
`Format('{%.8x-%.4x-%.4x-%.2x%.2x-%.2x%.2x%.2x%.2x%.2x%.2x}', [LongInt(D1),
D2, D3, D4[0] … D4[7]])` (sysuintf.inc:155). Its twin `StringToGUID` parses
the same form and raises `EConvertError` on a malformed one; add both.

**pxx:** the `TGuid` record, with fields `D1..D4`, already works.

**Accept:** a zeroed `TGuid` with `D1 := 1` gives
`{00000001-0000-0000-0000-000000000000}`.

### 5. `TList.Pack` and `TFPList.Pack` (S)

**FPC:** removes every `nil` entry and keeps the others in order. `Count`
shrinks and `Capacity` does not. It does not call `Notify`. `TList.Pack`
just calls `TFPList.Pack` (lists.inc:279, 805). pxx has neither.

**Accept:** `l.Add(Pointer(5)); l.Add(nil); l.Pack; writeln(l.Count,PtrInt(l[0]));`
gives `15`.

### 6. `PTypeInfo^.Name` (M)

**FPC:** `TTypeInfo = record Kind: TTypeKind; Name: ShortString; end`,
followed by the type data (typinfo.pp:230). `Name` is the canonical type
name: `TypeInfo(Integer)^.Name` is `LongInt` in objfpc mode.

**pxx:** `PTypeInfo` points to `TTypeInfoHdr` (typinfo.pas:204), which has
`Kind: Int64; NamePtr: PString; DataPtr`. The compiler emits that layout, so
it cannot change. Add a read-only `Name` to the record: an advanced-record
property or function returning `NamePtr^`. Enum `TypeInfo()` still gives a
bare `PEnumRTTI`, not this header (typinfo.pas:189), so `Name` on an enum
needs its own path, or at least a test that says what it does.

**Accept:** `writeln(PTypeInfo(TypeInfo(Integer))^.Name);` with
`uses TypInfo` gives `LongInt`.

### 7. `Align` (S)

**FPC:** two overloads, `Align(Addr: PtrUInt; Alignment: PtrUInt): PtrUInt`
and `Align(Addr: Pointer; Alignment: PtrUInt): Pointer`. Both compute
`t := Addr + Alignment - 1; Result := t - t mod Alignment`, so `Alignment`
does not have to be a power of two (generic.inc:2428).

**Accept:** `writeln(PtrUInt(Align(Pointer(13),8)));` gives `16`.

### 8. `Random` with no argument (S)

**FPC:** `Random: Extended` returns a value in [0, 1): the next 32-bit
generator output times 2^-32 (system.inc:666). pxx's `Random(range)` is in
`compiler/builtin/builtin.pas:316`, and `lib/rtl/random.pas` already has a
`RandomDouble`. Build the new overload on `__pxxRandNext32`, the same source
`Random(range)` uses at builtin.pas:586, so both overloads advance one
sequence. That sequence does not match FPC's, as documented in
[Coming from Free Pascal](../../docs/getting-started/from-fpc.md).

**Accept:** `d:=Random; writeln((d>=0) and (d<1));` gives `TRUE`.

### 9. `TCollection` and `TCollectionItem` (L)

**FPC** (classesh.inc, collect.inc):

- `TCollection.Create(AItemClass)` sets the item class.
  - `Add` builds `AItemClass.Create(Self)`, appends it and returns it.
  - `Insert(Index)` adds an item and moves it to `Index`.
  - `Delete(Index)` frees the item. `Clear` frees them all.
  - `Items[i]` and `Count`.
  - `BeginUpdate`/`EndUpdate` hold back `Update` calls until the count returns to 0.
  - `FindItemID(ID)`.
- `TCollectionItem.Create(ACollection)` adds itself to that collection.
  - `ID` is taken from the collection's counter, which only goes up.
  - `Index` can be read or written; writing it moves the item.
  - Setting `Collection` moves the item to another collection.
  - Freeing an item removes it from its collection.
  - `DisplayName` defaults to the class name.
- `TOwnedCollection` adds `Owner`.

Do `TCollectionEnumerator` too: the note at `lib/rtl/classes.pas:167` says
`TComponentEnumerator`'s `for in` row waits on it.

**Accept:** `col:=TCollection.Create(TCollectionItem); col.Add; col.Add;
writeln(col.Count,col.Items[1].Index);` gives `21`. Then write a test that
reads `ID` after a delete and an `Index` write, and checks it against fpc.

### 10. `IInterface` declared twice (S, check both sides)

**FPC:** `IInterface`, `IUnknown` and `TInterfacedObject` are in `System`,
and `TInterfacedObject` implements `IInterface`.

**pxx:** `compiler/builtin/builtinheap.pas:487` declares `IInterface` and
`TInterfacedObject`. `lib/rtl/classes.pas:67` declares a second
`IInterface`, and `IUnknown` as an alias of that second one. A program that
names `Classes` gets the second type, which `TInterfacedObject` does not
implement. Measured with pin v447:

- `io := TInterfacedObject.Create` with `io: IInterface` compiles under
  `uses SysUtils` and prints `TRUE`.
- With `Classes` added, it is refused: "class does not implement the interface".

**Fix:** make `classes.pas` use the builtin types instead of declaring its
own. Before removing it, check what uses the `Classes` copy, such as
`lib/rtl/testutils.pas:36` (`TNoRefCountObject = class(TObject, IInterface)`)
and the `HResult` next to it.

**Accept:** `io:=TInterfacedObject.Create; writeln(io<>nil);` gives `TRUE`
with the full probe uses clause.

### 11. `NewStr` and `DisposeStr` (M: a `PString` collision)

**FPC:** `PString = PAnsiString` (objpas.pp:40).
- `NewStr(const S: string): PString` returns `nil` for `''`. Otherwise it
  `New`s a string and copies `S` into it.
- `DisposeStr(S: PString)` does nothing for `nil` and `Dispose`s otherwise
  (sysstr.inc:20, 50).

**pxx:** `lib/rtl/typinfo.pas:53` already exports
`PString = ^TRttiStr`, a `string[256]` pointer used for RTTI names.
`sysutils.pas:270` and `resources.pas:11` avoid declaring a second one on
purpose. FPC calls the RTTI one `PShortString`. So the fix is:

1. Rename the typinfo pointer to `PShortString`, and update `resources.pas`
   and the RTTI readers with it.
2. Then declare FPC's `PString` with `NewStr` and `DisposeStr`.

That touches RTTI, so run the typinfo tests.

**Accept:** `ps:=NewStr('abc'); writeln(ps^); DisposeStr(ps);` gives `abc`.

### 12. `Sum`, `SumInt`, `Mean` (S)

**FPC:**
- `Sum(const data: array of Double): Float` and `Sum(data: PDouble; N: LongInt): Float`.
- `SumInt(array of Int64 | Integer): Int64`.
- `Mean(array of Double): Float` is `Sum / Length`.

`Float` is FPC's widest float; on pxx use `Double`. pxx's `math.pas` has none
of the three.

**Accept:** `writeln(Sum([1.0,2.0,3.5]):0:1);` gives `6.5`.

### 13. `SwapEndian` (S)

**FPC:** reverses the byte order of its argument and returns the same type.
There are overloads for `SmallInt`, `Word`, `LongInt`, `DWord`, `Int64` and
`QWord` (systemh.inc:899). The `NtoBE`/`BEtoN`/`NtoLE`/`LEtoN` family is
built on it.

**Accept:** `writeln(HexStr(SwapEndian(LongWord($11223344)),8));` gives
`44332211`.

### 14. `MaxValue` and `MinValue` (S)

**FPC:**
- `MaxValue`/`MinValue(const data: array of Double): Double`, and the
  `array of Integer): Integer` forms.
- The `(data: PDouble; N: Integer)` and `(data: PInteger; N: Integer)` forms.

They return the largest or smallest element, and start from `data[0]`, so an
empty array is not handled (math.pp:484–508).

**Accept:** `writeln(MaxValue([1.0,9.5,3.0]):0:1);` gives `9.5`.

## Owner decisions, not seat work

These differ on purpose, according to comments in the source. Each one
needs the owner to decide before any seat touches it.

- **`UTF8Decode`** returns its input unchanged in the default build. Under
  `{$define PXX_WIDE_PAYLOAD}` it decodes as FPC does:
  `Length(UTF8Decode('h'#$C3#$A9))` is 2, which I measured with pin v447.
  The reason is at `lib/rtl/sysutils.pas:630`: it is the Unicode string
  migration.
- **`Error(reRangeError)`** raises `ERangeError`, and the program exits with
  217. The comment at `lib/rtl/sysutils.pas:436` gives the reason: "an FPC
  program that has `uses sysutils` gets its runtime errors converted to
  exceptions … so `Error(reRangeError)` there surfaces as a catchable
  ERangeError". **That premise measures false.** With fpc 3.2.2, a program
  with `uses SysUtils, Classes, StrUtils, Math` that calls
  `Error(reRangeError)` prints "Runtime error 201" to standard error and
  exits with 201. The standing ruling ("language compliance, not
  error-handling compliance") may still keep the pxx behaviour, but its
  stated reason needs correcting.
- **`RunError`** writes "Runtime error N" to standard output
  (`compiler/builtin/builtin.pas:777`); FPC writes it to standard error. The
  exit code is the same. This is an S if the owner wants it changed, and it
  falls under the same ruling.
