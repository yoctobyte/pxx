{ SPDX-License-Identifier: Zlib }
unit basehook;
{ A Pascal base class with a VIRTUAL hook, for the NilPy subclass test.

  The hook must be `virtual` for a Python subclass to override it: Python methods
  are always virtual, Pascal's are not, so a non-virtual base method keeps calling
  its own implementation even when the subclass declares the same name. Any
  library meant to be subclassed from NilPy has to mark its hooks virtual. }
interface

type
  ConfigBase = class
  public
    n: Integer;
    constructor Create;
    function optionxform(const s: AnsiString): AnsiString; virtual;
    function normalize(const s: AnsiString): AnsiString;
  end;

implementation

function LowerStr(const s: AnsiString): AnsiString;
var i: Integer; r: AnsiString;
begin
  r := s;
  for i := 1 to Length(r) do
    if (r[i] >= 'A') and (r[i] <= 'Z') then r[i] := Chr(Ord(r[i]) + 32);
  LowerStr := r;
end;

constructor ConfigBase.Create;
begin
  n := 0;
end;

function ConfigBase.optionxform(const s: AnsiString): AnsiString;
begin
  optionxform := LowerStr(s);
end;

function ConfigBase.normalize(const s: AnsiString): AnsiString;
begin
  normalize := optionxform(s);
end;

end.
