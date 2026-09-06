program test_mgmt_operators_copy;
{ `class operator Copy(constref src; var dst)` — the ASSIGNMENT lifetime event.

  WHAT THIS PINS, and each row is here because a weaker one would pass while
  broken:

  COPY REPLACES THE COPY. TRep's operator assigns NEITHER field, so if any bulk
  copy still ran the destination would come out holding the SOURCE's values.
  It must come out holding its OWN. A fixture whose operator dutifully copies
  the fields cannot tell "the operator ran instead of the copy" from "the
  operator ran as well as the copy" — both print the same thing.

  THE DESTINATION ARRIVES UNFINALIZED, holding its previous value. The operator
  prints `dst.n(before)`, so a release-then-copy would show up as a changed
  number rather than as nothing at all.

  THREE SITES, and they are three different lowering paths rather than three
  spellings of one: a plain local, an ARRAY ELEMENT destination, and a FIELD of
  another record. Copy fires at all three under fpc.

  ADDREF IS NOT HERE AND IS STILL REFUSED. Measured: Copy and AddRef are
  disjoint sites, not two operators competing for one event — AddRef fires on
  the BY-VALUE PARAMETER copy and only that, which is why this program passes
  nothing by value. With both declared, each site still runs its own operator.
  test_mgmt_operators_addref_refused holds that half.
  feature-pascal-management-operators-copy-and-addref

  Also absent on purpose: `b := SomeFunc`. fpc materialises the result in a
  hidden temp in the CALLER and manages that temp too, so it prints an extra
  init/fin pair that has nothing to do with Copy — the divergence already
  recorded in test_mgmt_operators's header. Keeping it out is what lets this
  .expected be fpc 3.2.2's, byte for byte. }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TRep = record
    n: Integer;
    m: Integer;
    class operator Initialize(var a: TRep);
    class operator Finalize(var a: TRep);
    class operator Copy(constref src: TRep; var dst: TRep);
  end;
  THolder = record
    f: TRep;
    tag: Integer;
  end;

var
  seq: Integer;

class operator TRep.Initialize(var a: TRep);
begin
  seq := seq + 1;
  a.n := seq;
  a.m := 100 + seq;
  writeln('init n=', a.n);
end;

class operator TRep.Finalize(var a: TRep);
begin
  writeln('fin n=', a.n, ' m=', a.m);
end;

{ deliberately copies NEITHER field — see the header }
class operator TRep.Copy(constref src: TRep; var dst: TRep);
begin
  writeln('copy src.n=', src.n, ' dst.n(before)=', dst.n);
end;

procedure PlainLocal;
var a, b: TRep;
begin
  writeln('-- plain local, before: a.n=', a.n, ' b.n=', b.n);
  b := a;
  writeln('-- after b := a: b.n=', b.n, ' b.m=', b.m);
end;

procedure ArrayElement;
var a: TRep;
    arr: array[0..1] of TRep;
begin
  writeln('-- array element, before: arr[1].n=', arr[1].n);
  arr[1] := a;
  writeln('-- after arr[1] := a: arr[1].n=', arr[1].n);
end;

procedure RecordField;
var a: TRep;
    h: THolder;
begin
  h.tag := 9;
  writeln('-- record field, before: h.f.n=', h.f.n);
  h.f := a;
  writeln('-- after h.f := a: h.f.n=', h.f.n, ' tag=', h.tag);
end;

begin
  seq := 0;
  PlainLocal;
  ArrayElement;
  RecordField;
  writeln('done');
end.
