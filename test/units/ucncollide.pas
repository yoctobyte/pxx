unit ucncollide;
{ Uses unit ucnwidget AND declares a class named Ucnwidget. fpc refuses this
  ("Duplicate identifier"); pxx accepts it because NilPy shims need it
  (pil.pas: class Image beside unit image). Inside this unit the class wins.
  bug-a-a-class-named-after-a-used-unit-cannot-be-constructed-from-outside-that-unit }
{$MODE PXX}
interface
uses ucnwidget;
type
  Ucnwidget = class
  public
    n: Integer;
    constructor Create(v: Integer);
  end;
function MakeHere(v: Integer): Ucnwidget;
implementation
constructor Ucnwidget.Create(v: Integer);
begin n := v; end;
function MakeHere(v: Integer): Ucnwidget;
begin Result := Ucnwidget.Create(v * 10); end;
end.
