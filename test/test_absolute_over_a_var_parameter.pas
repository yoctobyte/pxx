program test_absolute_over_a_var_parameter;
{ `absolute` over an UNTYPED `var` parameter — the idiom untyped parameters
  exist for. It was refused with "absolute: target must not be a by-reference
  parameter", which mattered because an untyped `var x` has no other spelling:
  you get a name with no type, and the two ways to give it one are a hard cast
  and this. Turbo Pascal, Delphi and FPC code all use the second.
  bug-a-absolute-cannot-overlay-an-untyped-var-parameter

  The refusal's REASONING was right and its conclusion was not. A by-ref
  parameter's slot holds an address, so copying the target's Offset alone would
  alias the pointer word — eight bytes of address read as the user's data. The
  representation for "the storage is at this slot's contents" already existed;
  it is what IsRef means, and every read/write/@/SizeOf path already honours it.
  So the overlay copies the target's ADDRESSING MODE, not just its offset.

  Every row is byte-identical to fpc 3.2.2 on the same source, natively and
  under qemu on i386 / aarch64 / arm32 / riscv32.

  `const x` earns its row separately from `var x`: a const untyped parameter is
  by-ref too, and a read-only overlay must resolve through the same slot.

  The by-VALUE parameter rows were omitted when this test was written, because
  the write through the overlay was landing somewhere else and freezing a wrong
  answer would have been worse than the gap. They are here now: the cause was
  never the addressing (a by-value param and a local share ONE space), it was
  register residency reading a cached copy of a slot the overlay had written
  behind its back. bug-a-an-absolute-overlay-of-a-by-value-parameter-is-lost,
  and test_absolute_alias_survives_residency gates that half across -O levels. }
{$mode objfpc}{$H+}
type TRec = record a, b, c: Integer; end;

{ the motivating shape: zero n bytes of whatever the caller passed }
procedure Zap(var x; n: Integer);
var b: array[0..255] of Byte absolute x;
    i: Integer;
begin for i := 0 to n - 1 do b[i] := 0; end;

procedure Fill(var x; n: Integer; v: Byte);
var b: array[0..255] of Byte absolute x;
    i: Integer;
begin for i := 0 to n - 1 do b[i] := v; end;

{ const untyped parameter — by-ref as well, read-only }
function Sum(const x; n: Integer): Integer;
var b: array[0..255] of Byte absolute x;
    i, s: Integer;
begin s := 0; for i := 0 to n - 1 do s := s + b[i]; Sum := s; end;

{ a TYPED var parameter is the same mechanism }
procedure TypedVar(var i: Integer);
var b: array[0..3] of Byte absolute i;
begin b[0] := 9; b[1] := 0; b[2] := 0; b[3] := 0; end;

{ a SCALAR overlay, not just an array }
procedure ScalarOver(var x);
var w: Word absolute x;
begin w := $BEEF; end;

{ a RECORD overlay }
procedure RecOver(var x);
var r: TRec absolute x;
begin r.a := 11; r.b := 22; r.c := 33; end;

{ @overlay must be the CALLER's storage, not a local slot }
function AddrOf(var x): PtrUInt;
var b: array[0..3] of Byte absolute x;
begin AddrOf := PtrUInt(@b[0]); end;

{ a by-VALUE parameter: same frame space as a local, so the plain offset copy
  aliases it — and the write must be visible to a later READ of the parameter,
  which is what register residency used to break from -O2 up }
procedure ByValueArr(v: Integer; var outv: Integer);
var b: array[0..3] of Byte absolute v;
begin b[0] := 5; outv := v; end;

procedure ByValueScalar(v: Integer; var outv: Integer);
var w: Byte absolute v;
begin w := 5; outv := v; end;

{ SizeOf reports the OVERLAY's type, not the target's }
function SizeOfOverlay(var x): Integer;
var b: array[0..7] of Byte absolute x;
begin SizeOfOverlay := SizeOf(b); end;

var i, j: Integer; r: TRec; p: PtrUInt;
begin
  i := $01020304;            WriteLn('before   ', i);
  Zap(i, SizeOf(i));         WriteLn('zapped   ', i);
  Fill(i, SizeOf(i), 1);     WriteLn('filled   ', i);
                             WriteLn('sum      ', Sum(i, SizeOf(i)));
  r.a := 7; r.b := 8; r.c := 9;
  Zap(r, SizeOf(r));         WriteLn('rec      ', r.a, ' ', r.b, ' ', r.c);
  r.a := 1; r.b := 2; r.c := 3;
                             WriteLn('recsum   ', Sum(r, SizeOf(r)));
  i := $01020304; TypedVar(i);   WriteLn('typedvar ', i);
  i := 0;         ScalarOver(i); WriteLn('scalar   ', i);
  i := 0;         p := AddrOf(i);WriteLn('addr     ', p = PtrUInt(@i));
  RecOver(r);                    WriteLn('recover  ', r.a, ' ', r.b, ' ', r.c);
                                 WriteLn('sizeof   ', SizeOfOverlay(i));
  i := $01020304; ByValueArr(i, j);    WriteLn('byval    ', j);
  i := $01020304; ByValueScalar(i, j); WriteLn('byvalsc  ', j);
end.
