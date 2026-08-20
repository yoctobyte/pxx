{ SPDX-License-Identifier: Zlib }
unit strict_dialect_theirs_bad_unit;
{ EXTERNAL code with an UNDIRECTIVED overload and no dialect marking. Under
  --strict-overload this must be REJECTED. Before the ownership rescoping it was
  silently exempt -- `CurrentUnitIdx < 0` meant "the main program", so every unit
  was let through and the flag policed only the one file that is not FPC code. }
interface
function Quad(a: Integer): Integer;
function Quad(const a: AnsiString): AnsiString;
implementation
function Quad(a: Integer): Integer; begin Quad := a * 4; end;
function Quad(const a: AnsiString): AnsiString; begin Quad := a + a + a + a; end;
end.
