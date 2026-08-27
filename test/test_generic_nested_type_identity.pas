program test_generic_nested_type_identity;
{ A nested type's identity is PER-SPECIALIZATION and PER-OWNER. Two symptoms of
  one cause, both pinned here:

  1. Two generic templates that each declare a nested type of the same name
     (`TPair`): the second template's own `array of TPair` resolved to the
     FIRST template's, giving "no such member" on a field that is plainly
     there.
  2. A second specialization of ONE generic that has a nested type: compiled
     clean, first specialization ran correctly, second SEGFAULTED — it read the
     first's layout.

  Cause: AddClassLikeType registers a nested type under its QUALIFIED name once
  the bare name is taken in the unit, which is what keeps the instantiations
  distinct — but every FindNestedType call site keyed on a `.`, so a BARE
  reference from inside the owner's own body fell through to the flat unit table
  and found whichever was registered first. Whichever template was specialized
  SECOND broke, which is what identified the cause; swapping the order moved the
  error to the other one.

  TPair is not a hypothetical: every dictionary-shaped generic in
  Generics.Collections declares one, so corpus rung 6 needs both of these.

  All output matches fpc 3.2.2 -Mobjfpc byte for byte. }
type
  { --- symptom 1: two templates, SAME nested type name --- }
  generic TA<K, V> = class
  public type TPair = record aa: K; bb: V; end;
  private FA: array of TPair;
  public
    procedure Put(const a: K; const b: V);
    function KeyAt(i: LongInt): K;
    function Count: LongInt;
  end;

  generic TB<K, V> = class
  public type TPair = record cc: K; dd: V; end;   { same NAME, different fields }
  private FA: array of TPair;
  public
    procedure Put(const a: K; const b: V);
    function ValAt(i: LongInt): V;
    function Count: LongInt;
  end;

procedure TA.Put(const a: K; const b: V);
begin
  SetLength(FA, Length(FA) + 1);
  FA[High(FA)].aa := a; FA[High(FA)].bb := b;
end;
function TA.KeyAt(i: LongInt): K; begin Result := FA[i].aa; end;
function TA.Count: LongInt; begin Result := Length(FA); end;

procedure TB.Put(const a: K; const b: V);
begin
  SetLength(FA, Length(FA) + 1);
  FA[High(FA)].cc := a; FA[High(FA)].dd := b;
end;
function TB.ValAt(i: LongInt): V; begin Result := FA[i].dd; end;
function TB.Count: LongInt; begin Result := Length(FA); end;

type
  T1 = specialize TA<String, LongInt>;
  T2 = specialize TB<String, LongInt>;
  { --- symptom 2: a SECOND specialization of a template with a nested type --- }
  T3 = specialize TA<LongInt, LongInt>;
var
  x: T1; y: T2; z: T3;
begin
  x := T1.Create; x.Put('one', 1); x.Put('two', 2);
  WriteLn(x.Count, ' ', x.KeyAt(0));

  y := T2.Create; y.Put('k', 7);
  WriteLn(y.Count, ' ', y.ValAt(0));

  z := T3.Create; z.Put(10, 20);
  WriteLn(z.Count, ' ', z.KeyAt(0));
end.
