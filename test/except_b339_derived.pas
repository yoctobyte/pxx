{ SPDX-License-Identifier: Zlib }
unit except_b339_derived;
{ b339 helper: descendants the base unit never saw. EDeep is two levels down, so
  the parent walk has to be a WALK, not a single parent check. ENotMine descends
  from EOther, which proves the walk still DISCRIMINATES — it must not simply
  match everything. }
interface

uses SysUtils, except_b339_base;

type
  EDerived = class(EMyBase);
  EDeep    = class(EDerived);
  ENotMine = class(EOther);

procedure RaiseDerived;
procedure RaiseDeep;
procedure RaiseNotMine;

implementation

procedure RaiseDerived;
begin
  raise EDerived.Create('derived');
end;

procedure RaiseDeep;
begin
  raise EDeep.Create('deep');
end;

procedure RaiseNotMine;
begin
  raise ENotMine.Create('not mine');
end;

end.
