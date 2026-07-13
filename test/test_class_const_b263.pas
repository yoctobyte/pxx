program test_class_const_b263;
{ `const` and `class const` sections inside a class body (FPC/Delphi). Neither parsed:
  `const` fell into the FIELD parser, which demanded a ':' after the name.

  Parsed as GLOBAL constants, exactly as a nested `type` section in a class body already
  is — pxx does not scope class-local declarations (access control is unenforced
  project-wide), and a constant has no storage, so there is nothing to scope. `class
  const` and `const` are the same thing here: a constant is already per-class, not
  per-instance.

  The section also had to learn to STOP at a visibility marker — the same over-run that
  bit `class var` (b244): `strict private` after a const list was swallowed as the next
  const NAME. }
type
  TA = class
  const
    MaxItems = 16;
    Greeting = 'hi';
  strict private              { the const section must stop HERE, not eat `strict` }
    FN: Integer;
  public
    class const Version = 3;
    procedure Go;
    function N: Integer;
  end;

procedure TA.Go;
begin
  FN := MaxItems + Version;   { unqualified, inside a method }
end;

function TA.N: Integer;
begin
  N := FN;
end;

var
  a: TA;
begin
  a := TA.Create;
  a.Go;
  writeln('n=', a.N);
  writeln('greeting=', TA.Greeting);         { class-qualified string const }
  writeln('qualified=', TA.MaxItems, ' ', TA.Version);
  a.Free;
end.
