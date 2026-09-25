{$mode objfpc}{$H+}
program test_a_finalize_of_a_whole_fixed_array_walks_every_element;
{ Finalize(x) of a WHOLE FIXED ARRAY empties every element, and Dispose of a
  pointer to one releases every element.

  The array node carries its ELEMENT's type, so Finalize read `arrOfRec` as one
  record and finalized element 0 only, and desugared `arrOfStr` to `arr := ''`
  (which emptied element 0 only). fpc empties all of them. Dispose inherited
  the same misreading once it began finalizing its pointee.

  Line `fin:` prints the lengths left after Finalize -- all zero except the
  record field `tag` (7, unmanaged, untouched) and the unfinalized 2-D row
  (m[0][0], 1 digit of its length) and the Integer array (5, unmanaged). Line
  `init:` is Initialize's zero fill. The `shape` rows are heap growth per
  iteration of New/Dispose over a pointer to a fixed array (and one explicit
  Finalize(p^) + FreeMem); every one must read 0. }
type
  IThing = interface ['{6F1E2D3C-1A2B-4C5D-8E9F-0A1B2C3D4E5F}'] function N: Integer; end;
  TThing = class(TInterfacedObject, IThing) function N: Integer; end;
  TR = record s: AnsiString; n: Integer; end;
  TRArr = array[0..2] of TR; TSArr = array[0..2] of AnsiString;
  TIArr = array[0..2] of IThing; TVArr = array[0..2] of Variant;
  TPRArr = ^TRArr; TPSArr = ^TSArr; TPIArr = ^TIArr; TPVArr = ^TVArr;
  THold = record tag: Integer; names: TSArr; end;
  TIntArr = array[0..3] of Integer; TPIntArr = ^TIntArr;
function TThing.N: Integer; begin Result := 1; end;
var g: TRArr; gs: TSArr; h: THold; m: array[0..1, 0..2] of AnsiString; gi: TIntArr;
function Str(k: Integer): AnsiString; begin Result := Copy('abcdefghijklmnopq', 1, 2 + k mod 13); end;
procedure Shape(k, i: Integer);
var pr: TPRArr; ps: TPSArr; pi: TPIArr; pv: TPVArr; pn: TPIntArr;
begin
  case k of
    0: begin New(pr); pr^[2].s := Str(i); Dispose(pr); end;
    1: begin New(ps); ps^[1] := Str(i); ps^[2] := Str(i+1); Dispose(ps); end;
    2: begin New(pi); pi^[0] := TThing.Create; pi^[2] := TThing.Create; Dispose(pi); end;
    3: begin New(pv); pv^[1] := Str(i); Dispose(pv); end;
    4: begin New(pn); pn^[1] := i; Dispose(pn); end;
    5: begin New(ps); ps^[1] := Str(i); Finalize(ps^); FreeMem(ps); end;
  end;
end;
const N = 400;
var k, i: Integer; h0, d: Int64;
begin
  g[1].s := Str(3); g[2].s := Str(4); Finalize(g);
  gs[0] := Str(5); gs[2] := Str(6); Finalize(gs);
  h.tag := 7; h.names[1] := Str(7); Finalize(h.names);
  m[1][2] := Str(8); m[0][0] := Str(9); Finalize(m[1]);
  gi[2] := 5; Finalize(gi);
  WriteLn('fin: ', Length(g[1].s), Length(g[2].s), ' ', Length(gs[0]), Length(gs[2]), ' ',
          h.tag, Length(h.names[1]), ' ', Length(m[1][2]), Length(m[0][0]), ' ', gi[2]);
  Finalize(g); Finalize(gs);  { second Finalize releases nothing }
  gs[1] := Str(1); Initialize(gs); WriteLn('init: ', Length(gs[1]));
  for k := 0 to 5 do
  begin
    for i := 1 to 20 do Shape(k, i);
    h0 := GetFPCHeapStatus.CurrHeapUsed;
    for i := 1 to N do Shape(k, i);
    d := (Int64(GetFPCHeapStatus.CurrHeapUsed) - h0) div N;
    WriteLn('shape ', k, ' bytes/iter=', d);
  end;
end.
