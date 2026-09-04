unit unit_impl_private;
{ A unit with exactly one exported name and four private ones, for
  bug-p-a-units-implementation-section-is-visible-to-its-importers.

  The alias below is the SHIPPED bug in miniature: builtinheap declared a
  private `PWord = ^NativeInt` and, because FindTypeAlias is consulted before
  the builtin-name chain, it silently re-typed the builtin `PWord = ^UInt16`
  for every importer -- so `PWord(p)^ := x` wrote eight bytes where the source
  said two. Spelled here with the same disagreement (8 bytes vs 2) so the test
  beside it can tell the two meanings apart by VALUE, not by whether something
  compiled. }
interface

function ImplPrivateExported: Integer;

implementation

type
  PWord = ^NativeInt;          { disagrees with the builtin PWord = ^UInt16 }
  TImplOnlyRec = record x: Integer; end;

const
  IMPL_ONLY_CONST = 4242;

var
  ImplOnlyVar: Integer;

function ImplOnlyRoutine: Integer;
begin
  ImplOnlyRoutine := 7;
end;

function ImplPrivateExported: Integer;
var r: TImplOnlyRec; p: PWord; n: NativeInt;
begin
  { The unit's OWN implementation section stays fully visible to itself --
    that is the half of the rule an over-broad fix would break, so it is
    exercised here rather than assumed. All four private names are used. }
  n := -1;
  p := @n;
  r.x := ImplOnlyRoutine + IMPL_ONLY_CONST;
  ImplOnlyVar := r.x;
  if SizeOf(p^) <> SizeOf(NativeInt) then ImplOnlyVar := -1;
  ImplPrivateExported := ImplOnlyVar;
end;

end.
