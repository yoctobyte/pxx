{$mode objfpc}
program test_open_array_managed_field_record;

{ A fixed array of RECORDS WITH MANAGED FIELDS handed to an open-array param.
  The sibling of test_const_open_array_managed, which pins the same construct
  one type-level down (a managed ELEMENT, AnsiString). Both the const/value and
  the var paths in IRLowerCallArg used to exclude managed-field records, so the
  argument fell through to a bare headerless address: High() answered -1 and the
  callee's loop silently never ran; the >MAX_OPEN_ARRAY_STACK_TEMP form
  segfaulted outright.
  bug-a-a-static-array-of-managed-field-records-loses-its-length-as-an-open-array-argument

  The arms are the ones that can tell a wholesale copy-in/copy-out from a
  field-aware one: two managed fields per record, a dynamic-array field, a
  callee that copies an element into a LOCAL (a record assign with per-field
  ARC, released field-wise at scope exit), a callee that writes only element 0,
  and the heap-temp path above 64 KiB. Nothing here prints SizeOf: a managed
  field is 8 bytes on a 64-bit target and 4 on a 32-bit one, which would make
  the cross-target differential rows disagree for no defect.

  FPC 3.2.2 oracle is the expectation wired in the Makefile. }

type
  TM = record A, B: AnsiString; N: Integer; end;
  TD = record A: AnsiString; V: array of Integer; end;

{ const: read-only, and the field-wise release the old comment named }
function sumConst(const items: array of TM): Integer;
var loc: TM; k, n: Integer;
begin
  n := 0;
  for k := 0 to High(items) do
  begin
    loc := items[k];                       { per-field ARC into a local }
    n := n + Length(loc.A) + Length(loc.B);
  end;
  sumConst := n;
end;

{ var: writes must propagate back through the copy-out }
procedure mutAll(var items: array of TM);
var loc: TM; k: Integer;
begin
  for k := 0 to High(items) do
  begin
    loc := items[k];
    items[k].A := loc.A + '/' + loc.B;
    items[k].N := k;
  end;
end;

{ var, PARTIAL: only element 0 is written; the rest must survive untouched }
procedure mutFirst(var items: array of TM);
begin
  if High(items) >= 0 then items[0].A := 'ONLY0';
end;

{ a dynamic-array field rides the same wholesale move }
function sumDyn(const items: array of TD): Integer;
var k, j, n: Integer;
begin
  n := 0;
  for k := 0 to High(items) do
  begin
    n := n + Length(items[k].A);
    for j := 0 to High(items[k].V) do n := n + items[k].V[j];
  end;
  sumDyn := n;
end;

var
  a: array[0..1] of TM;
  d: array[0..1] of TD;
  big: array[0..4095] of TM;          { 4096 * (2 managed + Integer) > 64 KiB }
  i, t: Integer;
begin
  a[0].A := 'aa'; a[0].B := 'bb';
  a[1].A := 'ccc'; a[1].B := 'd';
  writeln('const sum=', sumConst(a), ' high=', High(a));
  mutAll(a);
  writeln('after var: ', a[0].A, ' ', a[1].A, ' n=', a[0].N, a[1].N);
  mutFirst(a);
  writeln('after partial: ', a[0].A, ' ', a[1].A);

  d[0].A := 'xy'; SetLength(d[0].V, 3); d[0].V[0] := 1; d[0].V[1] := 2; d[0].V[2] := 3;
  d[1].A := 'z';  SetLength(d[1].V, 1); d[1].V[0] := 10;
  writeln('dyn sum=', sumDyn(d));

  { heap-temp path: the same call above MAX_OPEN_ARRAY_STACK_TEMP }
  for i := 0 to 4095 do begin big[i].A := 'p'; big[i].B := 'qq'; end;
  writeln('big sum=', sumConst(big), ' high=', High(big));

  { repeat, so a leaked or double-freed handle shows as drift or a crash }
  t := 0;
  for i := 1 to 500 do
  begin
    a[0].A := 'aa'; a[0].B := 'bb'; a[1].A := 'ccc'; a[1].B := 'd';
    t := t + sumConst(a);
    mutAll(a);
  end;
  writeln('loop t=', t, ' ', a[0].A, ' ', a[1].A);
end.
