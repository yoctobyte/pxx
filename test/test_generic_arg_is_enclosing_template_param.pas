program test_generic_arg_is_enclosing_template_param;
{ A generic argument that is the ENCLOSING template's parameter must not be
  resolved eagerly into a concrete alias.

  `TCmp<TKey>` written inside `TDict<TKey, TValue>`'s body was minted as the
  concrete alias `TCmp$TKey` -- because the desugar tested an argument only
  against the template it was rewriting, and TKey belongs to a template that had
  not been parsed yet when TCmp's sweep ran. The streamed class body then said
  `Val: TKey` and reported `unknown type: TKey` from TCmp's own line, which the
  user never asked to be specialized.
  bug-p-a-generic-argument-that-is-another-templates-parameter-is-minted-as-a-concrete-type

  Row 4 is the other half of the boundary: a genuinely concrete argument must
  STILL be minted eagerly. A fix that defers everything passes rows 1-3 and
  breaks the feature.

  Expected values are FPC 3.2.2's. }
{$MODE DELPHI}

type
  TCmp<T> = class
    Val: T;
  end;

  TDict<TKey, TValue> = class
    C: TCmp<TKey>;
    K: TKey;
    V: TValue;
  end;

  { constrained parameter: the constraint names no parameter and must not be
    collected as one }
  TCon<T: TObject> = class
    Held: T;
  end;

  TUser<TItem: TObject> = class
    Box: TCon<TItem>;
    Tag: Integer;
  end;

  { `;`-separated parameter groups }
  TPairish<TA; TB> = class
    Inner: TCmp<TA>;
    N: Integer;
  end;

var
  ok, tot: Integer;
  d: TDict<Integer, LongInt>;
  u: TUser<TObject>;
  p: TPairish<Integer, LongInt>;
  c: TCmp<Integer>;

procedure Check(const nm: string; got, want: Integer);
begin
  tot := tot + 1;
  if got = want then begin ok := ok + 1; writeln('ok   ', nm); end
  else writeln('FAIL ', nm, ' = ', got, ' want ', want);
end;

begin
  ok := 0; tot := 0;

  d := TDict<Integer, LongInt>.Create;
  d.K := 5;
  d.V := 6;
  Check('enclosing param as a generic argument', d.K, 5);
  Check('second enclosing param', d.V, 6);

  u := TUser<TObject>.Create;
  u.Tag := 7;
  Check('constrained enclosing param', u.Tag, 7);

  p := TPairish<Integer, LongInt>.Create;
  p.N := 8;
  Check('semicolon-separated parameter groups', p.N, 8);

  { the other half: a concrete argument is still resolved eagerly }
  c := TCmp<Integer>.Create;
  c.Val := 9;
  Check('a concrete argument still specializes', c.Val, 9);

  writeln('total ok ', ok, ' / ', tot);
end.
