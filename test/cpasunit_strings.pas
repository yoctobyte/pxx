unit cpasunit_strings;
{ A Pascal unit whose BODY uses managed strings, imported from C by
  `#include "cpasunit_strings.pas"`. Nothing here is C-facing except the
  signatures: the point is that the body must compile and behave exactly as it
  does when the same unit is used from a Pascal program.

  Two defects lived behind this file, both in the C DRIVER and neither in the
  lowering (see bug-a-c-driver-omits-rtl-stubs-for-an-imported-pascal-unit):
  the driver emitted no AnsiString runtime shims, so the body called code
  offset 0; and it left CProgramMode on while parsing the unit, so a Pascal
  string literal in a concat was adjusted into a C `char*` and counted as ONE
  character. }
interface

function LitLen: Integer;               { literal assignment }
function ConcatVarLit: Integer;         { managed + literal — the +8 defect }
function ConcatLitVar: Integer;         { literal + managed }
function ConcatVarVar: Integer;
function ConcatChain: Integer;          { three literals }
function CharCodeAt(i: Integer): Integer;
procedure CopyTag(dst: PChar; cap: Integer);

implementation

function Build: AnsiString;
begin
  Build := 'pxx' + '-' + 'ok';
end;

function LitLen: Integer;
var s: AnsiString;
begin s := 'pxx-ok'; LitLen := Length(s); end;

function ConcatVarLit: Integer;
var a, s: AnsiString;
begin a := 'ab'; s := a + 'cdef'; ConcatVarLit := Length(s); end;

function ConcatLitVar: Integer;
var a, s: AnsiString;
begin a := 'ab'; s := 'cdef' + a; ConcatLitVar := Length(s); end;

function ConcatVarVar: Integer;
var a, b, s: AnsiString;
begin a := 'ab'; b := 'cdef'; s := a + b; ConcatVarVar := Length(s); end;

function ConcatChain: Integer;
var s: AnsiString;
begin s := 'ab' + 'cd' + 'ef'; ConcatChain := Length(s); end;

function CharCodeAt(i: Integer): Integer;
var s: AnsiString;
begin
  s := Build;
  if (i < 1) or (i > Length(s)) then CharCodeAt := -1
  else CharCodeAt := Ord(s[i]);
end;

procedure CopyTag(dst: PChar; cap: Integer);
var s: AnsiString; i: Integer;
begin
  s := Build;
  i := 0;
  while (i < Length(s)) and (i < cap - 1) do
  begin
    dst[i] := s[i + 1];
    i := i + 1;
  end;
  dst[i] := #0;
end;

end.
