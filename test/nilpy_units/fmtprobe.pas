{ SPDX-License-Identifier: Zlib }
unit fmtprobe;
{ Minimal stand-in for the RTL units a Python import reaches: it takes an
  `array of const`, which is what a .npy program could not compile against. }
interface

function describe(const a: AnsiString; n: Integer): AnsiString;
function joinconst(const args: array of const): Integer;

implementation

function joinconst(const args: array of const): Integer;
begin
  joinconst := High(args) + 1;
end;

function describe(const a: AnsiString; n: Integer): AnsiString;
begin
  describe := a + ':' + Chr(Ord('0') + joinconst([a, n]));
end;
end.
