{ A method may be NAMED `Default`.

  `default` lexes as its own token kind because the word is also a property
  modifier and an array default -- but those are MODIFIER positions, never a
  method-name position, so the two cannot be confused. Before this, declaring
  the method reported "expected method name" and pointed at the declaration,
  which reads as a syntax error in the surrounding class rather than as a
  reserved-word collision.

  It matters because `TComparer<T>.Default` is rtl-generics' central idiom and
  Delphi's own RTL spells it the same way -- and note the collision has nothing
  to do with generics: a plain class hit it just as hard, which is what made it
  look like a generics bug when it surfaced there.

  The property `default` modifier is exercised alongside it, because that is
  the construct a too-eager fix would break.

  Output verified against FPC 3.2.2.
  bug-p-a-method-cannot-be-named-Default }
program test_method_named_default;
{$mode objfpc}{$H+}
type
  TCmp = class
    class function Default: LongInt; static;
  end;

  TBox = class
  private
    F: array[0..3] of LongInt;
    function GetItem(i: LongInt): LongInt;
    procedure SetItem(i: LongInt; v: LongInt);
  public
    property Items[i: LongInt]: LongInt read GetItem write SetItem; default;
  end;

class function TCmp.Default: LongInt; begin Result := 8; end;
function TBox.GetItem(i: LongInt): LongInt; begin Result := F[i]; end;
procedure TBox.SetItem(i: LongInt; v: LongInt); begin F[i] := v; end;

var b: TBox;
begin
  WriteLn(TCmp.Default);
  b := TBox.Create;
  b[2] := 42;
  WriteLn(b[2]);
end.
