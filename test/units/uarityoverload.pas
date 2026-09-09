unit uarityoverload;
{ A generic method IMPLEMENTATION must bind to the template of the same name AND
  ARITY. Two templates of one name differing only in parameter count are legal
  Pascal and rtl-generics declares four such pairs; before 2026-09-09 four sites
  picked the LAST same-named template, so this unit's two-parameter bodies were
  attributed to the one-parameter overload and streamed under a substitution
  binding only T -- leaving H spelled, which is a type name in no scope.

  The unit form is load-bearing: the bodies must sit in an IMPLEMENTATION
  section, after the specializations in the interface, so they are buffered
  ahead of the parser rather than walked in place.
  bug-p-a-generic-method-implementation-is-attributed-by-name-not-arity }
{$MODE DELPHI}
interface
type
  THashA = record a: array[1..3] of Byte; end;   { SizeOf 3 }
  THashB = record a: array[1..7] of Byte; end;   { SizeOf 7 }

  TBase<T> = class
  end;

  TOrd<T, H> = class(TBase<T>)
    class function Tag: LongInt; static;
  end;

  TStr<T, H> = class(TBase<T>)
    class function Ordinal: LongInt; static;
  end;

  { the arity overloads -- one parameter, filling the second in }
  TStr<T> = class(TStr<T, THashA>);
  TOrd<T> = class(TOrd<T, THashA>);

  TStringOrd = class(TStr<string>);              { H = THashA, SizeOf 3 }
  TIntOrdB   = class(TStr<LongInt, THashB>);     { H = THashB, SizeOf 7 }

implementation

class function TOrd<T, H>.Tag: LongInt;
begin
  Result := SizeOf(H);
end;

{ The specialization here is in EXPRESSION position and its arguments are the
  enclosing template's own parameters -- the shape whose `specialize` marker is
  injected only when TOrd is declared, i.e. after this body may already have been
  buffered. }
class function TStr<T, H>.Ordinal: LongInt;
begin
  Result := TOrd<T, H>.Tag;
end;

end.
