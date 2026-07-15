program test_interface_com_value_param;
{$mode objfpc}{$H+}{$interfaces com}
{ COM value-parameter lifetime: a by-value interface param is a private owning
  reference — the callee may re-publish it (store to a global / longer-lived var)
  and the object must outlive the call. Regression for the double-release bug
  where the caller's by-value temp copy released the caller's single reference
  without a matching retain (silent use-after-free once the value escaped). }
type
  IThing = interface ['{B0000000-0000-0000-0000-000000000099}']
    procedure Go;
  end;
  TThing = class(TInterfacedObject, IThing)
    destructor Destroy; override;
    procedure Go;
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

var
  g: IThing;

procedure Stash(x: IThing);          { by-value: escapes into the global g }
begin
  g := x;
end;

procedure Borrow(const x: IThing);   { const: pure alias, no refcount change }
begin
  x.Go;
end;

procedure Ignore(x: IThing);         { by-value, never used — dies at caller exit }
begin
end;

procedure DoStash;
var t: IThing;
begin
  t := TThing.Create;                { rc=1 }
  Stash(t);                          { g now co-owns; must survive DoStash exit }
  Borrow(t);                         { const alias, no rc change }
  Ignore(t);                         { by-value copy retained+released, balanced }
end;                                 { t released; g still holds -> no free yet }

begin
  freed := 0;
  DoStash;
  writeln('after DoStash freed=', freed);   { expect 0 — g keeps it alive }
  g.Go;                                      { must not be a use-after-free }
  g := nil;                                  { last ref -> destructor runs }
  writeln('after nil freed=', freed);        { expect 1 }
end.
