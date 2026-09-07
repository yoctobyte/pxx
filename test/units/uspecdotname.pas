unit uspecdotname;
{ A PLAIN record deliberately spelled like the generic class in
  test_specialization_does_not_rename_after_a_dot.pas. Its whole job is to be
  named `TBox` in another unit, so that `uspecdotname.TBox` inside the template
  body is a UNIT-QUALIFIED reference to something that is not the template. }
{$mode objfpc}
interface
type
  TBox = record Tag: LongInt; end;
implementation
end.
