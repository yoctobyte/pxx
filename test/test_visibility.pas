program test_visibility;
{ Phase 0: class visibility section markers parse correctly.
  Access is intentionally NOT enforced (project policy) — every member is
  reachable regardless of section. This test proves all four section markers
  parse and that members declared in each section behave normally. The
  published flag itself is consumed by RTTI (Phase 1), not observable here. }
type
  TWidget = class
  private
    FTag: Integer;
  protected
    FKind: Integer;
  public
    Name: Integer;
    function GetTag: Integer;
  published
    Caption: Integer;
    property Tag: Integer read FTag write FTag;
  end;

function TWidget.GetTag: Integer;
begin
  GetTag := FTag;
end;

var
  w: TWidget;
begin
  w := TWidget.Create;
  { private field (access not enforced), read back via public method }
  w.FTag := 7;
  writeln(w.GetTag);
  { protected field — access not enforced }
  w.FKind := 3;
  writeln(w.FKind);
  { public field }
  w.Name := 42;
  writeln(w.Name);
  { published field }
  w.Caption := 99;
  writeln(w.Caption);
  { published property over private field }
  w.Tag := 123;
  writeln(w.Tag);
end.
