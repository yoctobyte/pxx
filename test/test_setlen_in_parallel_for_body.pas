program test_setlen_in_parallel_for_body;
{ The shape that actually motivated bug-a-setlength-on-a-captured-managed-string:
  a `parallel for` body calling SetLength on a captured AnsiString.

  The body is lifted with the string passed BY POINTER, so `SetLength(s, n)`
  inside it is a deref -- and the SetLength classifier only recognised a deref
  whose pointee was a dynamic ARRAY, never a managed string. `s := s + 'x'` in
  the same body compiled fine, which is what made this look like a threading
  problem rather than a lowering one.

  Positive control: `pinned` (992065f21f33) REFUSES this file with
  `SetLength expects a string variable in IR codegen`. Build --threadsafe. }
{$mode objfpc}{$H+}
uses palparallel;
var total: Int64;

procedure Run;
var i: LongInt; s: AnsiString; acc: Int64;
begin
  acc := 0;
  parallel(pdChunked) for i := 0 to 999 reduction(+: acc) do
  begin
    s := '';
    SetLength(s, 8);
    acc := acc + Length(s);
  end;
  total := acc;
end;

begin
  Run;
  WriteLn('PARALLEL SETLEN OK total=', total);
end.
