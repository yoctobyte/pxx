{ `@o.R.N` -- the ADDRESS of a field of a record field of a class instance --
  was refused with `a statement cannot start with '.'`, and fpc 3.2.2 -Mdelphi
  compiles it.

  ONE CAUSE, SEVERAL FACES. The `@` arm in pasparser_expr.inc special-cased a
  class base and consumed the object name, the dot and exactly ONE identifier,
  then took the address of that and stopped. There was no walk over further
  `.` or `[` selectors, so the rest of the designator was left in the token
  stream and whatever came next reported the error -- which is why the same
  defect reads as three unrelated bugs: `@o.R.Ev` gave `expected 'then' before
  '.'`, `@o.Items[0].Ev` gave `@obj.method: unknown method or field` (the name
  after the dot is a PROPERTY, so both FindUMeth and FindUField miss it), and
  `p := @o.R.N` gave the statement-parser error above. THE ERROR TEXT DEPENDS
  ON WHAT FOLLOWS THE TRUNCATED PARSE, NOT ON THE DEFECT.

  THE BOUNDARY IS THE CLASS BASE AND NOT THE SHAPE, which is what the control
  rows below are for: `@r.Inner.N` over a plain record and `@a[0].N` over an
  array element compiled throughout, because both go through ParseLValueAST,
  which has always walked the whole chain. One opener of three -- the same
  shape as every other bug in this family, and the reason the fix is a
  delegation to ParseClassRecordSelectors rather than a sixth hand-rolled
  selector loop.
  bug-p-at-over-a-class-base-consumes-only-one-selector
  refactor-p-three-hand-rolled-postfix-loops }
program test_at_over_a_class_base_walks_every_selector;
{$mode delphi}
type
  TInner = record N: Boolean; M: LongInt; end;
  TSub = class
  public
    V: LongInt;
    R: TInner;
  end;
  TOwner = class
  private
    FItems: array[0..2] of TSub;
    function GetIt(i: LongInt): TSub;
  public
    Sub: TSub;
    R: TInner;
    Arr: array[0..2] of TInner;
    N: Boolean;
    { A PROPERTY IS THE THIRD MEMBER KIND AND THE ARM KNEW TWO. `@o.Items[0].V`
      was refused with `@obj.method: unknown method or field` -- not by the
      missing selector walk, but one step earlier, by a name lookup that asked
      FindUMeth and FindUField and stopped. Same sentence as the implicit-deref
      rule's own guard, which enumerated field and method and not property.
      A row whose FIRST selector is a property is the only one that can see it. }
    property Items[i: LongInt]: TSub read GetIt;
    constructor Create;
  end;
constructor TOwner.Create;
var k: LongInt;
begin
  for k := 0 to 2 do FItems[k] := TSub.Create;
end;
function TOwner.GetIt(i: LongInt): TSub;
begin
  Result := FItems[i];
end;
var
  o: TOwner;
  r: record Inner: TInner; end;
  a: array[0..1] of TInner;
  pv: ^LongInt;
  pb: ^Boolean;
begin
  o := TOwner.Create;
  o.Sub := TSub.Create;
  o.Items[0].V := 48; o.Items[2].R.M := 49;
  o.Sub.V := 42; o.Sub.R.M := 43;
  o.R.M := 44; o.R.N := True;
  o.Arr[2].M := 45; o.Arr[2].N := True;
  o.N := False;
  r.Inner.N := True; r.Inner.M := 46;
  a[0].N := True; a[0].M := 47;

  { the controls: bases that were never broken, so a fix that breaks them shows }
  pb := @o.N;          WriteLn('ctl class 1 dot   ', pb^);
  pb := @r.Inner.N;    WriteLn('ctl record 2 dots ', pb^);
  pv := @r.Inner.M;    WriteLn('ctl record int    ', pv^);
  pb := @a[0].N;       WriteLn('ctl array elem    ', pb^);
  pv := @a[0].M;       WriteLn('ctl array int     ', pv^);

  { the rows this test exists for: a CLASS base and more than one selector }
  pv := @o.R.M;        WriteLn('class .R.M        ', pv^);
  pb := @o.R.N;        WriteLn('class .R.N        ', pb^);
  pv := @o.Sub.V;      WriteLn('class .Sub.V      ', pv^);
  pv := @o.Sub.R.M;    WriteLn('class .Sub.R.M    ', pv^);
  pv := @o.Arr[2].M;   WriteLn('class .Arr[2].M   ', pv^);
  pb := @o.Arr[2].N;   WriteLn('class .Arr[2].N   ', pb^);
  pv := @o.Items[0].V; WriteLn('class .Items[0].V ', pv^);
  pv := @o.Items[2].R.M; WriteLn('class .It[2].R.M  ', pv^);

  { and the addresses must be WRITEABLE, not merely readable: a walk that
    resolved the wrong offset would still print the value it happened to land
    on. Written through the pointer, read back through the object. }
  pv := @o.Sub.R.M;    pv^ := 91;   WriteLn('store .Sub.R.M    ', o.Sub.R.M);
  pv := @o.Arr[2].M;   pv^ := 92;   WriteLn('store .Arr[2].M   ', o.Arr[2].M);
  pb := @o.R.N;        pb^ := False; WriteLn('store .R.N        ', o.R.N);
  pv := @o.Items[0].V; pv^ := 93;   WriteLn('store .Items[0].V ', o.Items[0].V);

  WriteLn('AT SELECTOR WALK OK');
end.
