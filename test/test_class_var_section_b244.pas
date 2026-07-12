program test_class_var_section_b244;
{ `class var` is a SECTION: its name list must stop at the next visibility marker
  or member word. Those lex as plain identifiers, so the name loop used to eat
  `public` as another class-var name and then demand a ':' (bug-pascal-class-var-
  section-eats-visibility). A bare class-var name inside a method must resolve
  too — keyed on the owning class, not Self, so it also works in a `class
  procedure`, which is static and has no Self. }
type
  TCounter = class
  protected
    class var Hits: Integer;
    class var A, B: Integer;
  public
    class procedure Bump;
    procedure Touch;
    function Total: Integer;
  end;

class procedure TCounter.Bump;
begin
  Hits := Hits + 1;   { bare class var in a STATIC method (no Self) }
end;

procedure TCounter.Touch;
begin
  Hits := Hits + 10;  { bare class var in an INSTANCE method }
  A := 3;
  B := 4;
end;

function TCounter.Total: Integer;
begin
  Total := Hits + A + B;
end;

var c: TCounter;
begin
  TCounter.Bump;
  TCounter.Bump;
  c := TCounter.Create;
  c.Touch;
  writeln('hits=', TCounter.Hits);   { shared slot, reachable via the class }
  writeln('viaobj=', c.Hits);        { ...and via an instance }
  writeln('total=', c.Total);
  c.Free;
end.
