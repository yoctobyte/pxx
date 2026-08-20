{ SPDX-License-Identifier: Zlib }
unit strict_dialect_ours_unit;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Stands in for our RTL: undirectived overloads, which the PXX dialect allows by
  design. --strict-overload must NOT judge this file, because it declares the
  dialect it is written in. }
interface
function Twice(a: Integer): Integer;
function Twice(const a: AnsiString): AnsiString;
implementation
function Twice(a: Integer): Integer; begin Twice := a * 2; end;
function Twice(const a: AnsiString): AnsiString; begin Twice := a + a; end;
end.
