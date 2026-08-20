program test_mgmt_operators_copy_refused;
{ `class operator Copy`/`AddRef` are RECOGNISED — the spelling is not a syntax
  error — but they fire on a value COPY, a lifetime event nothing dispatches
  yet. Accepting one would give a record whose invariant never runs, which is
  worse than not compiling, so it is refused by name.
  feature-pascal-management-operators-copy-and-addref }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TFoo = record
    n: Integer;
    class operator Copy(constref src: TFoo; var dst: TFoo);
  end;
class operator TFoo.Copy(constref src: TFoo; var dst: TFoo);
begin dst.n := src.n; end;

begin
end.
