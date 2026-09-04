{ Unit A of test_generic_shadow_import: declares `TBox<T>` AND specializes it
  itself. That second half is what separates the two halves of the fix -- with
  no `TBox$Integer` minted here, the importer's shadowing declaration succeeds
  on the uses-clause skip alone.
  bug-p-a-generic-declaration-does-not-shadow-an-imported-one-of-the-same-name }
unit ugshadowa;
{$MODE DELPHI}

interface

type
  TBox<T> = record FromA: T; end;

function AUsesItsOwn: Integer;

implementation

function AUsesItsOwn: Integer;
var b: TBox<Integer>;
begin
  b.FromA := 11;
  Result := b.FromA;
end;

end.
