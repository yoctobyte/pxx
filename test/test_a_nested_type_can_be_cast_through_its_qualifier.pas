program test_a_nested_type_can_be_cast_through_its_qualifier;
{ A NESTED TYPE RESOLVED IN A DECLARATION AND IN SizeOf/Low/Default, AND NOT IN
  A TYPECAST:

    TPlain = class type TPFn = function(const a, b: LongInt): LongInt; end;

    var f: TPlain.TPFn;          { compiled                                  }
    SizeOf(TPlain.TPFn)          { answered 8, matching fpc                  }
    TPlain.TPFn(@Cmp)            -> class method not found (TPFn)
    inst.TPFn(@Cmp)              -> "TPFn": no such member on this record/class

  So the NAME resolved and only the CAST position did not know how to reach it,
  two positions with two different messages because each fell through to a
  different walk. Both messages are about MEMBERS, for a type declared three
  lines above.

  THE FIFTH ABSENT COPY OF EatQualifiedTypePrefix, which is exactly what that
  function's own header predicts: it names ParseTypeKindInner, SizeOf, Default
  (found by a tdefault8 SEGFAULT) and Low/High as four sites that each failed by
  NOT having the strip, and a typecast is a fifth position nobody enumerated.
  Its remedy applies too -- the sites were found "by a probe drawn from the
  GRAMMAR rather than from any helper's call graph, which by construction only
  returns sites that already reach the helper".

  ROWS 1-6 ARE ONE DEFECT AND NOT SIX. All seven nested kinds were refused
  identically (procedural, subrange, enum, array, class, plain alias, and the
  record left out here only because its cast needs a `^`), on a plain
  NON-GENERIC class and on pin v407, so the generics in fpc's tgeneric10 are
  incidental to it. Rows 9 and 10 carry the specialization spelling anyway,
  because that is the one real code writes.

  ROWS 11-14 ARE THE POSITIVE CONTROL AND THEY ARE THE POINT OF THE FIXTURE.
  A cast arm that fires on `TOwner.<name>(` will happily eat `TOwner.Method(`,
  and a fixture of rows 1-10 alone passes while the compiler has stopped being
  able to call a class method. `Ident` is an ordinary class function; `TColor`
  is a class function whose name COLLIDES with a global enum type, which is the
  case the unscoped half of ClassDeclaresTypeNamed admits and the member check
  excludes. MEASURED, not argued: with that one line removed and nothing else
  changed, `shadow=` and `ishad=` print 5 -- the cast's answer -- instead of 502.
  Both rows return x*100+k precisely so a captured call cannot COLLIDE with the
  cast's value; `TColor(5)` and `Ident(5)` would both have printed 5 and the
  control could not have failed.

  Row 15 is the global type of that name still being castable, so the fix is not
  paid for by shadowing it in the other direction.

  All fifteen rows measured against fpc 3.2.2.
  bug-p-a-nested-type-can-be-declared-through-a-qualifier-but-not-cast-through-one
  Burns tgeneric10.pp. }
{$mode objfpc}{$H+}
type
  TColor = (cRed, cGreen, cBlue);
  TRawArr = array[0..3] of LongInt;
  TBox = class end;

  generic TWrap<T> = class
  type
    TCmp = function(const a, b: T): T;
  end;

  TPlain = class
  type
    TPFn    = function(const a, b: LongInt): LongInt;
    TPRange = 1..9;
    TPEnum  = (peA, peB, peC);
    TPArr   = array[0..3] of LongInt;
    TPCls   = class(TBox) end;
    TPInt   = LongInt;
    class function Ident(x: LongInt): LongInt;
    class function TColor(x: LongInt): LongInt;
  end;

  TWL = specialize TWrap<LongInt>;

class function TPlain.Ident(x: LongInt): LongInt; begin Ident := x * 100 + 1; end;
class function TPlain.TColor(x: LongInt): LongInt; begin TColor := x * 100 + 2; end;

function Cmp(const a, b: LongInt): LongInt; begin Cmp := b - a; end;

var inst: TPlain; wl: TWL; raw: TRawArr; obj: TBox; n: LongInt;
begin
  inst := TPlain.Create; wl := TWL.Create; obj := TPlain.TPCls.Create;
  n := 5; raw[0] := 42;
  WriteLn('proc  = ', TPlain.TPFn(@Cmp)(1, 9));
  WriteLn('range = ', Ord(TPlain.TPRange(n)));
  WriteLn('enum  = ', Ord(TPlain.TPEnum(1)));
  WriteLn('array = ', TPlain.TPArr(raw)[0]);
  WriteLn('alias = ', TPlain.TPInt(n));
  WriteLn('class = ', Ord(TPlain.TPCls(obj) is TBox));
  WriteLn('iproc = ', inst.TPFn(@Cmp)(1, 9));
  WriteLn('ienum = ', Ord(inst.TPEnum(1)));
  WriteLn('spec  = ', TWL.TCmp(@Cmp)(1, 9));
  WriteLn('ispec = ', wl.TCmp(@Cmp)(1, 9));
  WriteLn('meth  = ', TPlain.Ident(n));
  WriteLn('imeth = ', inst.Ident(n));
  WriteLn('shadow= ', TPlain.TColor(n));
  WriteLn('ishad = ', inst.TColor(n));
  WriteLn('global= ', Ord(TColor(1)));
end.
