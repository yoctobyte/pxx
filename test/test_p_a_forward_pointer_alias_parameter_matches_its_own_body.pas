{ A METHOD PARAMETER TYPED THROUGH A FORWARD POINTER ALIAS, WITH THE BODY
  WRITTEN AFTER A CALL TO IT.

  THE THREE LINES AT THE TOP ARE THE TEST, IN THIS ORDER AND IN ONE TYPE
  SECTION: `PItem = ^TItem` ABOVE `TItem`, and the class that takes a `PItem`
  parameter in the SAME section. Move the record above the alias, or the class
  into a second `type` section, and the bug does not reproduce — both of those
  put the alias's pointee in place before the method declaration is parsed.
  Do not tidy this file into either shape.

  WHAT IT PINS. While the alias is an unresolved forward, its element carries
  the PLACEHOLDER the pending-pointer arm leaves (tyInteger), not a pointee
  anyone wrote. A field, an array element and a function result all get repaired
  when ResolvePendingPointerAliases runs; a PARAMETER has no such column, so the
  declaration kept the placeholder and the implementation header — parsed after
  the pass — recorded the real record. FindProcOverloadRec's typed-pointer arm
  split the two, the body registered a SECOND proc, and the declaration's entry
  never got an address.

  THE SYMPTOM IS NOT LOCAL AND IT IS NOT A PARSE ERROR. It lands at CODEGEN as
  `unresolved forward: TAdder.Add`, reported against `builtinheap.pas` with a
  note suggesting an unterminated comment — a real file the author never wrote.
  `Later` below is what makes it fire: a call reached BEFORE the body binds to
  the bodiless entry. `Earlier` is the same routine with its body written first
  and is the NEGATIVE control — it compiled before this fix and must keep
  compiling.

  THE POSITIVE CONTROL IS THE PINNED COMPILER: it refuses this file outright.
  A green here before the fix would mean the file has been tidied.

  Measured on FPC's own compiler, which is where it was found:
  `PViHashListItem = ^TViHashListItem` sits eleven lines above its record in
  cclasses.pas and `TViHashList.AddToHashTable` takes one, so this single
  defect stood between pxx and that unit.
  Expected output is fpc 3.2.2's for this exact source.
  bug-p-a-method-parameter-typed-through-a-forward-pointer-alias-never-matches-its-own-body }
program test_p_a_forward_pointer_alias_parameter_matches_its_own_body;
{$mode objfpc}{$H+}

type
  PItem = ^TItem;
  TItem = record
    V: Integer;
    Next: PItem;
  end;

  TAdder = class(TObject)
  public
    Total: Integer;
    { The call is here and the body is at the bottom of the implementation. }
    procedure Later(p: PItem);
    procedure Earlier(p: PItem);
    procedure DriveLater(p: PItem);
    procedure DriveEarlier(p: PItem);
    function  Fetch(p: PItem): PItem;
  end;

{ DriveLater calls Later BEFORE Later's body exists -- the failing order. }
procedure TAdder.DriveLater(p: PItem);
begin
  Later(p);
end;

{ Earlier's body comes before its caller: the shape that already worked. }
procedure TAdder.Earlier(p: PItem);
begin
  Total := Total + p^.V * 10;
end;

procedure TAdder.DriveEarlier(p: PItem);
begin
  Earlier(p);
end;

{ A pointer-alias parameter AND a pointer-alias RESULT, so the pointee is
  proved still known after the fix rather than merely accepted: `Next` is read
  through the returned pointer, which is offset 8 and not offset 0. An elem type
  that had been forgotten answers here and not on `p^.V`. }
function TAdder.Fetch(p: PItem): PItem;
begin
  Fetch := p^.Next;
end;

procedure TAdder.Later(p: PItem);
begin
  Total := Total + p^.V;
end;

var
  a: TAdder;
  one, two: TItem;
begin
  two.V := 7;  two.Next := nil;
  one.V := 3;  one.Next := @two;

  a := TAdder.Create;
  a.DriveLater(@one);
  WriteLn('later    ', a.Total);
  a.DriveEarlier(@one);
  WriteLn('earlier  ', a.Total);
  WriteLn('fetch    ', a.Fetch(@one)^.V);
  WriteLn('direct   ', a.Fetch(@one)^.Next = nil);
  a.Free;
end.
