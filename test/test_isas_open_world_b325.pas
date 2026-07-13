{ `is` / `as` must recognise a subclass from a LATER-compiled unit/program (b325).

  IRLowerClassMatch enumerated the target's descendant VMTs when the site's OWN
  unit lowered — a subclass declared later was not in the set, so `FList[Index]
  as TJSONData` Halt(1)-trapped on fpjson's program-registered TMyNull factory
  class. Class targets now walk the RTTI blobs' parent chain at runtime
  (__pxxInheritsFrom), open-world; interface targets keep the enumeration.
  Bare TObject.Create instances are also safe: the builtin root now carries a
  real (empty) VMT, so its instances have a valid identity word (before, `o is
  T` on one walked garbage). }
program test_isas_open_world_b325;
{$mode objfpc}{$h+}
uses isas_b325_base;

type
  TLater = class(TThing)
    function Describe: String; override;
  end;

function TLater.Describe: String;
begin
  Result := 'later';
end;

var
  L: TObject;
  P: TObject;
begin
  L := TLater.Create;
  Writeln('is=', IsThing(L));                { unit's is-site, later subclass }
  Writeln('as=', PassesAs(L).Describe);      { unit's as-site + virtual dispatch }
  P := TObject.Create;
  Writeln('plain is=', IsThing(P));          { root instance: false, no crash }
end.
