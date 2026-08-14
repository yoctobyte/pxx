program TestFormatSingleArg;
{ A Single passed through `array of const`. Every float tags vtExtended -- FPC
  has no vtSingle -- so the BOX must be 8 bytes wide whatever the element's
  width is, because every consumer reads it as PDoubleRec(v.VExtended)^.

  It used to be allocated at the ELEMENT's width, so a Single got 4 bytes and
  the reader took those plus the 4 adjacent stack bytes:

    Format('%g', [aSingle])  ->  5.122630465115234E-315   for 0.1

  which is exactly Single(0.1)'s 0x3DCCCCCD read as the low half of a double.
  Silent garbage, and unfixable at the reader: no tag distinguishes the two
  widths (vtInteger/vtInt64 are a pair; floats are not, by FPC's design).

  Every line below is byte-identical to FPC 3.2.2. The values are the exact
  Double widenings of the Singles, which is what FPC prints too -- 0.1 as a
  Single really is 0.10000000149011612.
  bug-a-a-single-in-array-of-const-is-boxed-4-bytes-and-read-as-8 }
uses sysutils;
type TR = record f: Single; end;
var s: Single; r: TR; a: array[0..1] of Single; e: Extended; d: Double;
begin
  s := 0.1; r.f := 2.5; a[0] := 3.75; a[1] := -0.5; e := 1.25; d := 7.5;
  WriteLn(Format('%g',   [s]));
  WriteLn(Format('%.4f', [s]));
  WriteLn(Format('%e',   [s]));
  { the shape the value arrives in must not matter: variable, field, element,
    expression -- the widening is at the box, not at any one producer }
  WriteLn(Format('%.4f', [r.f]));
  WriteLn(Format('%.4f %.4f', [a[0], a[1]]));
  WriteLn(Format('%.4f', [s * 2]));
  { adjacent boxes must not overlap, and a Double alongside must be untouched }
  WriteLn(Format('%.4f %d %.4f %s', [s, 42, d, 'x']));
  WriteLn(Format('%.4f %.4f', [s, r.f]));
  { Extended takes the same branch; it is aliased to Double in this RTL }
  WriteLn(Format('%.4f', [e]));
end.
