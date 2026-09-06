unit urename;
{$mode objfpc}{$H+}
{ The implementation spells the type parameter DIFFERENTLY from the interface --
  <T> declared, <S> implemented. FPC rejects this (tgenfunc17, tgenfunc18);
  PXX's generics surface accepts a differing impl-side spelling deliberately,
  the same rule as tgeneric20/tgeneric30. }
interface
generic function Id<T>(a: T): T;
implementation
generic function Id<S>(a: S): S;
begin Result := a; end;
end.
