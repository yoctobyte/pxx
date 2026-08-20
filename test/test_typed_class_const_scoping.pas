program test_typed_class_const_scoping;
{ A TYPED class/record const (`const X: T = ...`) must be SCOPED to its owner.

  It was not. The untyped forms got a ClassConst registry row and a mangled
  backing name; the typed form kept its BARE name and ordinary global storage —
  "rare; tracked as a follow-up", said the note beside it. The consequence was
  not just that `TFoo.X` could not resolve it: two owners declaring the same
  const name shared ONE slot, so TA's method read TB's value with no
  diagnostic. Rows A and B of each pair are what makes that visible; a test
  with a single class passes either way.

  Records were the same bug one level out, and worse: their const section was
  parsed with NO owner at all (`ParseConstSection(-1, 0)`), on the reasoning
  that "a constant has no storage and pxx does not scope declarations". Both
  halves are false for a typed const. That is also why a type HELPER — which is
  a record — could not reach `UInt32.SIZED_SIGN_MASK[i]`, the open item in
  feature-pascal-type-helpers v3; it resolves through this same registry now.

  Untyped consts (K) are in the same program on purpose: they already worked,
  and the fix must not disturb them. Every row diffed against FPC 3.2.2 with
  {$modeswitch advancedrecords}.
  bug-p-two-classes-typed-consts-of-the-same-name-collide }
type
  TRA = record
    const TAG: array[1..2] of Integer = (10, 11);
    const K = 1;
    function G: Integer;
  end;
  TRB = record
    const TAG: array[1..2] of Integer = (20, 21);
    const K = 2;
    function G: Integer;
  end;
  TCA = class
    const S: Integer = 100;
    class function G: Integer; static;
  end;
  TCB = class
    const S: Integer = 200;
    class function G: Integer; static;
  end;
function TRA.G: Integer; begin G := TAG[1] + K; end;
function TRB.G: Integer; begin G := TAG[1] + K; end;
class function TCA.G: Integer; begin G := S; end;
class function TCB.G: Integer; begin G := S; end;
var ra: TRA; rb: TRB;
begin
  Writeln('rec  A bare : ', ra.G, ' (want 11)');
  Writeln('rec  B bare : ', rb.G, ' (want 22)');
  Writeln('rec  A qual : ', TRA.TAG[2], ' ', TRA.K, ' (want 11 1)');
  Writeln('rec  B qual : ', TRB.TAG[2], ' ', TRB.K, ' (want 21 2)');
  Writeln('cls  A      : ', TCA.G, ' ', TCA.S, ' (want 100 100)');
  Writeln('cls  B      : ', TCB.G, ' ', TCB.S, ' (want 200 200)');
end.
