{$define PXX_WIDE_PAYLOAD}
program test_pwidechar_cast;
{ `PWideChar(w)` — the cast, which did not exist. `var p: PWideChar` DECLARED
  fine (ParseTypeKind has a pwidechar arm setting the element to tyWideChar),
  but `p := PWideChar(w)` was "undefined variable (PWideChar)". fcl-xml's
  xmlutils.pp:285 writes `IsXmlName(PWideChar(Value), Length(Value), Xml11)`.

  It shares the PChar arm rather than copying it — the pointer operation is
  identical and only the ELEMENT differs — so the PChar rows below are here as
  the CONTROL: they take the same code and must be unchanged by the
  generalisation.

  The file defines PXX_WIDE_PAYLOAD because without it the cast is REFUSED, and
  that refusal is deliberate rather than a gap. Measured on 'hi' in a default
  build: `w[1]` is 104 in both pxx and FPC — indexing steps one byte through the
  UTF-8 payload and widens, which is right for ASCII by construction — but
  `PWideChar(w)[0]` steps TWO bytes and yields 26984 ($6968, 'h' and 'i'
  packed) where FPC gives 104. So the cast does not inherit WideString's
  existing UTF-8 divergence, it introduces a NEW one, on plain ASCII, where
  nobody would look. Refusing loudly beats a plausible wrong value; the gate is
  tracked by
  chore-a-decide-whether-widestring-can-come-out-from-behind-pxx-wide-payload
  and retiring it is what actually unblocks fcl-xml.

  Oracle: FPC (-Mdelphi), which prints these six lines (it has no such gate, so
  it compiles this file with the define simply ignored). }
var
  w: WideString;
  p: PWideChar;
  s: AnsiString;
  q: PChar;
begin
  w := 'hi';
  p := PWideChar(w);
  WriteLn('w0 ', Ord(p[0]));      { 'h' — two-byte step over UTF-16 units }
  WriteLn('w1 ', Ord(p[1]));      { 'i' — proves the STRIDE, not just the base }
  WriteLn('wd ', Ord(p^));        { deref arm, same element type }
  s := 'hi';
  q := PChar(s);                  { control: the arm this generalisation touched }
  WriteLn('c0 ', Ord(q[0]));
  WriteLn('c1 ', Ord(q[1]));
  WriteLn('cd ', Ord(q^));
end.
