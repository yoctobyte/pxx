{ SPDX-License-Identifier: Zlib }
unit strict_dialect_theirs_unit;
{ Stands in for EXTERNAL FPC code (Synapse, fgl, fpjson): NO dialect marking, so
  --strict-overload holds it to FPC's rules. FPC-conformant code carries the
  `overload` directive, so this compiles clean — which is the half that proves
  the flag polices external units WITHOUT rejecting correct FPC code.
  strict_dialect_theirs_bad_unit is the other half. }
interface
function Thrice(a: Integer): Integer; overload;
function Thrice(const a: AnsiString): AnsiString; overload;
implementation
function Thrice(a: Integer): Integer; overload; begin Thrice := a * 3; end;
function Thrice(const a: AnsiString): AnsiString; overload; begin Thrice := a + a + a; end;
end.
