program test_generic_nested_type_field_name;
{ A generic class's NESTED type may name a field after one of the class's own
  type parameters: the nested record is its own scope, so `record k: K` is legal
  and FPC 3.2.2 accepts it. This is TDictionary<K,V>.TPair's exact shape, and it
  is what corpus rung 6 (rtl-generics) runs into first.

  Specialization is token-based -- it rewrote every identifier matching a type
  parameter name, and Pascal is case-INSENSITIVE, so the FIELD `k` was rewritten
  alongside the TYPE `K`. `record k: K; v: V; end` became `record String: String`
  and the matching `FA[i].k` became `FA[i].String`, reported as
  "String: no such member" -- a diagnostic naming a type where a field belongs,
  and pointing at the use rather than at the substitution that broke it.

  Both spellings are pinned: fields that collide with a type parameter (k/v) and
  fields that do not (kk/vv), because the fix must leave the non-colliding path
  exactly as it was.

  Deliberately ONE specialization per template, and distinct nested type NAMES:
  two templates sharing a nested type name, and a second specialization of one
  template that has a nested type, are two separate open defects that would mask
  this one. See bug-p-two-generic-templates-cannot-share-a-nested-type-name and
  bug-p-a-second-specialization-of-a-generic-with-a-nested-type-segfaults. }
type
  generic TD<K, V> = class
  public type
    TDPair = record k: K; v: V; end;      { names COLLIDE with K and V }
  private
    FA: array of TDPair;
  public
    procedure Put(const a: K; const b: V);
    function KeyAt(i: LongInt): K;
    function ValAt(i: LongInt): V;
    function Count: LongInt;
  end;

  generic TE<K, V> = class
  public type
    TEPair = record kk: K; vv: V; end;    { names do NOT collide -- the control }
  private
    FA: array of TEPair;
  public
    procedure Put(const a: K; const b: V);
    function KeyAt(i: LongInt): K;
    function Count: LongInt;
  end;

procedure TD.Put(const a: K; const b: V);
begin
  SetLength(FA, Length(FA) + 1);
  FA[High(FA)].k := a;
  FA[High(FA)].v := b;
end;
function TD.KeyAt(i: LongInt): K; begin Result := FA[i].k; end;
function TD.ValAt(i: LongInt): V; begin Result := FA[i].v; end;
function TD.Count: LongInt; begin Result := Length(FA); end;

procedure TE.Put(const a: K; const b: V);
begin
  SetLength(FA, Length(FA) + 1);
  FA[High(FA)].kk := a;
  FA[High(FA)].vv := b;
end;
function TE.KeyAt(i: LongInt): K; begin Result := FA[i].kk; end;
function TE.Count: LongInt; begin Result := Length(FA); end;

type
  TStrInt = specialize TD<String, LongInt>;
  TPlain  = specialize TE<String, LongInt>;
var
  a: TStrInt; c: TPlain;
begin
  a := TStrInt.Create;
  a.Put('one', 1); a.Put('two', 2);
  WriteLn(a.Count, ' ', a.KeyAt(0), ' ', a.ValAt(1));
  c := TPlain.Create;
  c.Put('x', 9);
  WriteLn(c.Count, ' ', c.KeyAt(0));
end.
