unit procslot;
{ A Pascal unit with a PROCEDURAL field and two ways to fill it: from Pascal
  with `@TheMaker`, and from a caller that hands the routine in as an argument.
  The second is the one NilPy got wrong -- it stored the callable-value carrier
  where the slot wants a code address.
  bug-n-a-pascal-function-handed-to-a-procedural-parameter-from-nilpy-is-not-a-code-address }
interface
type
  TMakeFn = function(laden, room: Integer): Integer;
  TKindRec = class
    build: TMakeFn;
  end;
function TheMaker(laden, room: Integer): Integer;
function MkKindWired: TKindRec;
function MkKind(f: TMakeFn): TKindRec;
function CallItFromPascal(k: TKindRec): Integer;
implementation
function TheMaker(laden, room: Integer): Integer;
begin Result := laden * 100 + room; end;
function MkKindWired: TKindRec;
begin Result := TKindRec.Create; Result.build := @TheMaker; end;
function MkKind(f: TMakeFn): TKindRec;
begin Result := TKindRec.Create; Result.build := f; end;
function CallItFromPascal(k: TKindRec): Integer;
begin Result := k.build(5, 2); end;
end.
