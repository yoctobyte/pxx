{ SPDX-License-Identifier: Zlib }
unit isas_b325_base;
{ b325 helper: the `as`/`is` sites live HERE, compiled before the program
  declares its own subclass. }
interface

type
  TThing = class
    function Describe: String; virtual;
  end;

function PassesAs(O: TObject): TThing;
function IsThing(O: TObject): Boolean;

implementation

function TThing.Describe: String;
begin
  Result := 'thing';
end;

function PassesAs(O: TObject): TThing;
begin
  Result := O as TThing;
end;

function IsThing(O: TObject): Boolean;
begin
  Result := O is TThing;
end;

end.
