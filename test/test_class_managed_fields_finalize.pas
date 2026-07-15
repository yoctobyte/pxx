program test_class_managed_fields_finalize;
{$mode objfpc}{$H+}
{ Class managed-field finalization on Free
  (bug-a-class-managed-fields-not-finalized-on-destroy): a COM interface /
  ansistring / dynarray field of a CLASS is released when the object is freed —
  after the whole Destroy chain, before FreeMem (FPC FreeInstance timing),
  dispatched on the RUNTIME class via the [VMT-16] layout backlink. Also pins
  the ARC balance: a field store retains, so a live alias survives the free. }
type
  IThing = interface ['{B0000000-0000-0000-0000-000000000099}']
    procedure Go;
  end;
  TThing = class(TInterfacedObject, IThing)
    destructor Destroy; override;
    procedure Go;
  end;
  THolder = class
    f: IThing;
    s: string;
    d: array of Integer;
    destructor Destroy; override;
  end;
  { descendant adds its own managed field; freed via a BASE-typed variable the
    runtime dispatch must still release it }
  THolder2 = class(THolder)
    f2: IThing;
  end;

var
  freed: Integer;
  order: string;

destructor TThing.Destroy;
begin
  freed := freed + 1;
  order := order + 'T';
  inherited Destroy;
end;

procedure TThing.Go; begin end;

destructor THolder.Destroy;
begin
  order := order + 'H';
  inherited Destroy;
end;

procedure Basic;
var h: THolder;
begin
  h := THolder.Create;
  h.f := TThing.Create;
  h.s := 'abc' + 'def';
  SetLength(h.d, 100);
  h.Free;                          { destructor first, THEN the field release }
end;

procedure Aliased;
var h: THolder; li: IThing; ls: string;
begin
  h := THolder.Create;
  li := TThing.Create;             { rc=1 }
  h.f := li;                       { rc=2 }
  ls := 'keep-' + 'me';
  h.s := ls;
  h.Free;                          { rc back to 1; ls must survive }
  writeln('alias freed=', freed);  { still the Basic one only }
  writeln('ls=', ls);
  li := nil;                       { rc=0 -> destroy }
end;

procedure Runtime;
var b: THolder;                    { BASE-typed variable }
begin
  b := THolder2.Create;
  b.f := TThing.Create;
  THolder2(b).f2 := TThing.Create;
  b.Free;                          { runtime class releases BOTH fields }
end;

begin
  freed := 0; order := '';
  Basic;
  writeln('basic freed=', freed, ' order=', order);   { 1, HT }
  Aliased;
  writeln('after alias freed=', freed);               { 2 }
  freed := 0;
  Runtime;
  writeln('runtime freed=', freed);                   { 2 }
end.
