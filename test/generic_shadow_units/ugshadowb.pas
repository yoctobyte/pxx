{ Unit B: declares its OWN `TBox<T>` in its interface and imports A's in its
  implementation, so three distinct templates named TBox are live at once by the
  time the program is parsed. B must still see ITS OWN.

  Its member is named `FromB` and A's `FromA` on purpose: a wrong resolution is
  then a COMPILE error naming the member, not a value that happens to match.
  bug-p-a-generic-declaration-does-not-shadow-an-imported-one-of-the-same-name }
unit ugshadowb;
{$MODE DELPHI}

interface

type
  TBox<T> = record FromB: T; end;

function BUsesItsOwnAndA: Integer;

implementation

uses ugshadowa;

function BUsesItsOwnAndA: Integer;
var b: TBox<Integer>;
begin
  b.FromB := 22;
  Result := b.FromB + AUsesItsOwn;
end;

end.
