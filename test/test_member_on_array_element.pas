program test_member_on_array_element;
{ A `.member` on an ARRAY ELEMENT whose type is not a record.

  bug-p-a-member-on-an-array-element-silently-reads-the-elements-own-bytes: the
  fall-through built a field access at offset 0 and read the element's own
  bytes, so `a[0].NoSuchMember` COMPILED and printed a pointer as an integer,
  and `ai[0].NoSuch` printed the element itself with the selector silently
  dropped. Two guards for that exact hole already existed one routine away and
  both were keyed on the receiver being a plain declared variable, which an
  AN_INDEX node is not.

  This is the ACCEPT side, and it is the half that keeps the fix honest: the
  shape has a valid reading — a type helper on the element — and FPC compiles
  it. A fix that merely refused everything would pass a refusal-only test.
  The refusal side is test/refuse/member_on_array_element_*.pas, driven from the
  Makefile.

  FPC 3.2.2 (in $mode delphi -- spelled without braces because a Pascal comment
  cannot contain its own delimiter and FPC does not nest them) answers zz / yy / 14 / 1 / kk / zzzz —
  verified against this exact program, not assumed. }
type
  TStrHelper = record helper for AnsiString
    function Twice: AnsiString;
  end;
  TIntHelper = record helper for Integer
    function Dbl: Integer;
  end;
  TR = record x: Integer; end;

function TStrHelper.Twice: AnsiString;
begin Twice := Self + Self; end;

function TIntHelper.Dbl: Integer;
begin Dbl := Self + Self; end;

var
  a: array[0..1] of AnsiString;
  ai: array[0..1] of Integer;
  ar: array[0..1] of TR;
  d: array of AnsiString;
begin
  a[0] := 'z'; a[1] := 'y';
  ai[0] := 7;
  ar[0].x := 1;
  SetLength(d, 1); d[0] := 'k';

  WriteLn(a[0].Twice);        { helper on a static-array element }
  WriteLn(a[1].Twice);        { ...and the element index is not ignored }
  WriteLn(ai[0].Dbl);         { the same on a non-managed element type }
  WriteLn(ar[0].x);           { a RECORD element still takes its own path }
  WriteLn(d[0].Twice);        { and a DYNAMIC array element materialises too }
  WriteLn(a[0].Twice.Twice);  { chained: the temp is a receiver in its turn }
end.
