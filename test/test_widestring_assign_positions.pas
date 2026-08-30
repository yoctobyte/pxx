{ The width CONVERSION at an assignment, enumerated by the position of the
  destination -- a record field and an array element, not just a plain variable,
  and in both directions.

  Non-ASCII ON PURPOSE, and this is the whole reason the test exists. On ASCII a
  UTF-8 byte count and a UTF-16 unit count are the same number, so an ASCII
  version of this file passes with the conversion entirely absent; three bugs in
  this campaign survived on exactly that. 'cafe' with an acute e is 5 UTF-8
  bytes and 4 UTF-16 units, and Ord of the 4th unit is 233 (U+00E9) if the
  transcode happened and 195 (0xC3, the first byte of the UTF-8 pair) if it did
  not.

  ORACLE CONDITION, and it is not the codepage directive. FPC reproduces these
  numbers only with `cwstring` in the uses clause:

    fpc -Mobjfpc -FcUTF8 <this file, plus `uses cwstring;`>

  Without it FPC's default widestring manager widens byte-for-byte -- 5 units,
  last=195 -- and neither {$codepage utf8} nor -FcUTF8 changes that, because the
  knob is the manager and not the source encoding. An earlier note in this
  campaign blamed the codepage directive; it was the wrong knob. Compared under
  that condition, every line below matches FPC exactly.
  feature-unicodestring-model }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}{$codepage utf8}
{$define PXX_WIDE_PAYLOAD}
program WideAssignPositions;
type
  TR = record w: WideString; n: AnsiString; end;
  TWArr = array[0..1] of WideString;
var
  r: TR;
  s: AnsiString;
  w: WideString;
  wa: TWArr;
begin
  s := 'café';
  r.w := s;      WriteLn('narrow->widefield  len=', Length(r.w), ' last=', Ord(r.w[4]));
  w := 'café';
  r.n := w;      WriteLn('wide->narrowfield  len=', Length(r.n));
  wa[0] := s;    WriteLn('narrow->widearrel  len=', Length(wa[0]), ' last=', Ord(wa[0][4]));
  s := r.w;      WriteLn('widefield->narrow  len=', Length(s));
  w := wa[0];    WriteLn('widearrel->wide    len=', Length(w), ' last=', Ord(w[4]));
end.
