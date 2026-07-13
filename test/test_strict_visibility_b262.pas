program test_strict_visibility_b262;
{ `strict private` / `strict protected` (FPC/Delphi). pxx does not enforce access at all
  (project policy), so `strict` adds nothing to enforce — it is consumed and the section
  behaves as the plain visibility that follows. Unconsumed, `strict` was read as a FIELD
  name and demanded a ':'.

  The published section after a strict one must still register RTTI: the visibility flag
  is what drives the published-method table, so a mis-parsed marker would silently change
  what is reflectable. }
uses rtti;

type
  TA = class
  strict private
    FX: Integer;
  strict protected
    procedure Bump;
  private
    procedure AlsoHidden;
  public
    procedure Go;
    property X: Integer read FX;
  published
    procedure TestVisible;
  end;

procedure TA.Bump;        begin FX := FX + 1; end;
procedure TA.AlsoHidden;  begin FX := FX + 100; end;
procedure TA.Go;          begin Bump; Bump; end;
procedure TA.TestVisible; begin end;

var
  a: TA;
  i: Integer;
begin
  a := TA.Create;
  a.Go;
  writeln('x=', a.X);

  { only the published one is reflectable — the strict/private ones must NOT be }
  writeln('published-count=', PublishedMethodCount(a));
  for i := 0 to PublishedMethodCount(a) - 1 do
    writeln('published=', PublishedMethodName(a, i));
  writeln('bump-hidden=', FindPublishedMethod(a, 'Bump') = nil);
  a.Free;
end.
