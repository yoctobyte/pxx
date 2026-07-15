program test_interface_com_record_field;
{$mode objfpc}{$H+}{$interfaces com}
{ COM interface as a record FIELD: managed exactly like an ansistring field —
  zero-initialised, retained on record copy, released on record finalization.
  Regression for the field being treated as a plain (unmanaged) pointer, which
  leaked the object on scope exit and dropped no reference on record copy. }
type
  IThing = interface ['{B0000000-0000-0000-0000-000000000099}']
    procedure Go;
  end;
  TThing = class(TInterfacedObject, IThing)
    destructor Destroy; override;
    procedure Go;
  end;
  TRec = record
    f: IThing;
    n: Integer;
  end;

var
  freed: Integer;

destructor TThing.Destroy;
begin
  freed := freed + 1;
  inherited Destroy;
end;

procedure TThing.Go;
begin
  writeln('go');
end;

procedure UseOne;
var r: TRec;
begin
  r.f := TThing.Create;              { rc=1 }
  r.f.Go;
end;                                 { r.f released -> rc=0 -> destructor }

procedure Copied;
var a, b: TRec;
begin
  a.f := TThing.Create;              { rc=1 }
  b := a;                            { record copy retains f -> rc=2 }
  b.f.Go;
end;                                 { a.f and b.f both released -> one destroy }

begin
  freed := 0;
  UseOne;
  writeln('after UseOne freed=', freed);   { expect 1 }
  Copied;
  writeln('after Copied freed=', freed);    { expect 2 (single object, one free) }
end.
