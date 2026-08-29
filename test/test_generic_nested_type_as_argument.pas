program test_generic_nested_type_as_argument;
{ A type declared INSIDE a template's body is meaningless until that template is
  specialized, exactly like one of its parameters — so it must not be resolved
  eagerly into a concrete alias either.

  `TEnum<TPair>` where TPair is nested in `TDict<TKey, TValue>` was minted as
  `TEnum$TPair`, and the streamed class body then said `Cur: TPair` and reported
  `unknown type: TPair` from TEnum's own line.
  bug-p-a-nested-type-of-the-enclosing-template-is-minted-as-a-concrete-generic-argument

  The parameter half of this was fixed first and this walked straight through
  it, which is why both are now collected by ONE procedure rather than two.

  The last two rows are the boundary in the other direction, and both were live
  hazards in the fix rather than decoration: a genuinely concrete argument must
  STILL be minted, and a method's DEFAULT PARAMETER VALUE must not register its
  type as a nested declaration — `procedure P(a: Integer = 0)` is an `Ident =`
  inside a class body, and reading it as one would have deferred every
  `TBox<Integer>` in the file.

  NOT WIRED INTO THE MAKEFILE YET, deliberately: it still fails. Half of the
  defect is fixed (the group is no longer minted eagerly -- `--debug` shows
  `paramform=TRUE` where it showed FALSE), and the remaining half is in the
  nested-PREREQUISITE emitter, which writes `TEnum$TPair = specialize
  TEnum<TPair>` at the top level with `TPair` un-substituted, where no such type
  exists. See the ticket. Wiring a red rule into `test-core` would be a landmine;
  this file is the reduction, and it goes green with the rule when the second
  half lands.

  Expected values are FPC 3.2.2's. }
{$MODE DELPHI}

type
  TEnum<T> = class
    Cur: T;
  end;

  TDict<TKey, TValue> = class
  type
    TPair = record
      K: TKey;
      V: TValue;
    end;
  var
    E: TEnum<TPair>;
    N: Integer;
    procedure SetN(a: Integer = 7);
  end;

  { visibility keyword before `type`, and a pointer-to-parameter alias — the
    shape rtl-generics uses (`public type PT = ^T;`) }
  TBag<T> = class
  public type
    PT = ^T;
  public
    Ptr: TEnum<PT>;
    M: Integer;
  end;

var
  ok, tot: Integer;
  d: TDict<Integer, LongInt>;
  b: TBag<Integer>;
  e: TEnum<Integer>;

procedure TDict<TKey, TValue>.SetN(a: Integer = 7);
begin
  N := a;
end;

procedure Check(const nm: string; got, want: Integer);
begin
  tot := tot + 1;
  if got = want then begin ok := ok + 1; writeln('ok   ', nm); end
  else writeln('FAIL ', nm, ' = ', got, ' want ', want);
end;

begin
  ok := 0; tot := 0;

  d := TDict<Integer, LongInt>.Create;
  d.N := 4;
  Check('nested record as a generic argument', d.N, 4);
  d.SetN(11);
  Check('method on the enclosing template still works', d.N, 11);
  d.SetN;
  Check('a default parameter value is not a nested type decl', d.N, 7);

  b := TBag<Integer>.Create;
  b.M := 6;
  Check('public type PT = ^T as a generic argument', b.M, 6);

  e := TEnum<Integer>.Create;
  e.Cur := 9;
  Check('a concrete argument still specializes', e.Cur, 9);

  writeln('total ok ', ok, ' / ', tot);
end.
